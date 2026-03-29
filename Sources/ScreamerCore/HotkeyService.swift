import ApplicationServices
import Carbon.HIToolbox
import Foundation

public struct GlobalHotkey: Sendable, Equatable {
    public let keyCode: CGKeyCode
    public let modifiers: CGEventFlags
    public let displayValue: String

    public init(keyCode: CGKeyCode, modifiers: CGEventFlags, displayValue: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayValue = displayValue
    }

    public static let optionSpace = GlobalHotkey(
        keyCode: CGKeyCode(kVK_Space),
        modifiers: [.maskAlternate],
        displayValue: "⌥Space"
    )
}

public protocol HotkeyServiceProtocol: AnyObject {
    var hotkeyDisplayValue: String { get }
    var isRunning: Bool { get }

    @discardableResult
    func start(onPress: @escaping @Sendable () -> Void) -> Bool

    func stop()
}

public final class HotkeyService: HotkeyServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let hotkey: GlobalHotkey
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var workerThread: Thread?
    private var onPress: (@Sendable () -> Void)?
    private var startupSemaphore: DispatchSemaphore?
    private var startupSucceeded = false

    public init(hotkey: GlobalHotkey = .optionSpace) {
        self.hotkey = hotkey
    }

    public var hotkeyDisplayValue: String {
        hotkey.displayValue
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return eventTap != nil
    }

    @discardableResult
    public func start(onPress: @escaping @Sendable () -> Void) -> Bool {
        lock.lock()
        if eventTap != nil {
            self.onPress = onPress
            lock.unlock()
            return true
        }

        self.onPress = onPress
        let semaphore = DispatchSemaphore(value: 0)
        startupSemaphore = semaphore
        startupSucceeded = false

        let thread = Thread { [weak self] in
            self?.runEventTapLoop()
        }
        thread.name = "Screamer.HotkeyEventTap"
        workerThread = thread
        lock.unlock()

        thread.start()
        let didSignal = semaphore.wait(timeout: .now() + 2) == .success

        lock.lock()
        let didStart = didSignal && startupSucceeded
        startupSemaphore = nil
        lock.unlock()

        if didStart == false {
            stop()
        }

        return didStart
    }

    public func stop() {
        lock.lock()
        let localRunLoop = runLoop
        if let localTap = eventTap {
            CGEvent.tapEnable(tap: localTap, enable: false)
        }
        onPress = nil
        lock.unlock()

        if let localRunLoop {
            CFRunLoopPerformBlock(localRunLoop, CFRunLoopMode.defaultMode.rawValue) {}
            CFRunLoopWakeUp(localRunLoop)
            CFRunLoopStop(localRunLoop)
        }
    }

    private func runEventTapLoop() {
        autoreleasepool {
            let mask = (1 << CGEventType.keyDown.rawValue)
            guard
                let localEventTap = CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .headInsertEventTap,
                    options: .defaultTap,
                    eventsOfInterest: CGEventMask(mask),
                    callback: { proxy, eventType, event, userInfo in
                        guard let userInfo else {
                            return Unmanaged.passUnretained(event)
                        }
                        let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
                        return service.handleEvent(proxy: proxy, type: eventType, event: event)
                    },
                    userInfo: Unmanaged.passUnretained(self).toOpaque()
                )
            else {
                completeStartup(success: false)
                return
            }

            let localRunLoop = CFRunLoopGetCurrent()
            let localSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, localEventTap, 0)
            CFRunLoopAddSource(localRunLoop, localSource, .defaultMode)
            CGEvent.tapEnable(tap: localEventTap, enable: true)

            lock.lock()
            eventTap = localEventTap
            runLoop = localRunLoop
            runLoopSource = localSource
            lock.unlock()

            completeStartup(success: true)
            CFRunLoopRun()

            lock.lock()
            eventTap = nil
            runLoop = nil
            runLoopSource = nil
            workerThread = nil
            lock.unlock()
        }
    }

    private func completeStartup(success: Bool) {
        lock.lock()
        startupSucceeded = success
        let semaphore = startupSemaphore
        lock.unlock()
        semaphore?.signal()
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let localTap = eventTap
            lock.unlock()
            if let localTap {
                CGEvent.tapEnable(tap: localTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        guard isRepeat == false else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let supportedMask: CGEventFlags = [
            .maskCommand,
            .maskShift,
            .maskControl,
            .maskAlternate,
            .maskSecondaryFn,
        ]
        let normalizedFlags = event.flags.intersection(supportedMask)

        guard keyCode == hotkey.keyCode, normalizedFlags == hotkey.modifiers else {
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let callback = onPress
        lock.unlock()
        callback?()

        // Consume the hotkey event so Option+Space does not leak into foreground apps.
        return nil
    }
}
