import AppKit
import ApplicationServices
import Carbon.HIToolbox

public protocol PasteboardWriting: Sendable {
    func write(_ value: String) -> Bool
}

public protocol AccessibilityChecking: Sendable {
    var isAccessibilityGranted: Bool { get }
}

public protocol PasteEventPosting: Sendable {
    func postCommandV() -> Bool
}

extension PermissionsService: AccessibilityChecking {}

public struct SystemPasteboard: PasteboardWriting {
    public init() {}

    public func write(_ value: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(value, forType: .string)
    }
}

public struct SystemPasteEvents: PasteEventPosting {
    public init() {}

    public func postCommandV() -> Bool {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let commandDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
            ),
            let commandUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
            )
        else {
            return false
        }

        commandDown.flags = .maskCommand
        commandUp.flags = .maskCommand
        commandDown.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
        return true
    }
}

public struct PasteHelper: Sendable {
    public enum Result: Sendable, Equatable {
        case pastedAndCopied
        case copiedOnly
        case copyFailed
    }

    private let pasteboard: any PasteboardWriting
    private let accessibility: any AccessibilityChecking
    private let pasteEvents: any PasteEventPosting

    public init(
        pasteboard: any PasteboardWriting = SystemPasteboard(),
        accessibility: any AccessibilityChecking = PermissionsService(),
        pasteEvents: any PasteEventPosting = SystemPasteEvents()
    ) {
        self.pasteboard = pasteboard
        self.accessibility = accessibility
        self.pasteEvents = pasteEvents
    }

    public func copyAndPaste(_ value: String) -> Result {
        guard pasteboard.write(value) else {
            return .copyFailed
        }

        guard accessibility.isAccessibilityGranted else {
            return .copiedOnly
        }

        return pasteEvents.postCommandV() ? .pastedAndCopied : .copiedOnly
    }

    public func copyOnly(_ value: String) -> Result {
        pasteboard.write(value) ? .copiedOnly : .copyFailed
    }
}
