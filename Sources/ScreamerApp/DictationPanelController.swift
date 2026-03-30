import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class DictationPanelController {
    private final class NonActivatingPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private var panel: NonActivatingPanel?
    private var stateCancellable: AnyCancellable?
    private var dismissTask: Task<Void, Never>?
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private weak var dictationController: DictationController?
    private var previousState: DictationController.State = .idle

    func bind(to dictationController: DictationController) {
        self.dictationController = dictationController

        if localEscapeMonitor == nil {
            localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleEscapeIfNeeded(event)
                return event
            }
        }
        if globalEscapeMonitor == nil {
            globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleEscapeIfNeeded(event)
            }
        }

        stateCancellable = dictationController.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                self?.handleStateChange(newState)
            }
    }

    func teardown() {
        dismissTask?.cancel()
        stateCancellable?.cancel()
        stateCancellable = nil
        dismissTask = nil

        if let localEscapeMonitor {
            NSEvent.removeMonitor(localEscapeMonitor)
            self.localEscapeMonitor = nil
        }
        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }

        panel?.orderOut(nil)
        panel = nil
    }

    private func handleStateChange(_ state: DictationController.State) {
        announceStateChangeIfNeeded(state)

        switch state {
        case .idle:
            dismissTask?.cancel()
            dismissTask = nil
            panel?.orderOut(nil)

        case .recording, .transcribing:
            dismissTask?.cancel()
            dismissTask = nil
            showPanel(for: state)

        case .success, .error:
            showPanel(for: state)
            dismissTask?.cancel()
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                panel?.orderOut(nil)
            }
        }

        previousState = state
    }

    private func showPanel(for state: DictationController.State) {
        let panel = self.panel ?? createPanel()
        panel.contentView = NSHostingView(rootView: DictationPanelView(state: state))
        position(panel: panel)
        panel.orderFrontRegardless()
    }

    private func createPanel() -> NonActivatingPanel {
        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 116),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        self.panel = panel
        return panel
    }

    private func position(panel: NSPanel) {
        guard let targetScreen = primaryMenuBarScreen() else { return }
        let visibleFrame = targetScreen.visibleFrame
        let panelSize = panel.frame.size
        let x = visibleFrame.midX - (panelSize.width / 2)
        let y = visibleFrame.minY + 40
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func primaryMenuBarScreen() -> NSScreen? {
        let origin = NSPoint(x: 0, y: 0)
        return NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.screens.first
    }

    private func handleEscapeIfNeeded(_ event: NSEvent) {
        guard event.keyCode == UInt16(kVK_Escape) else { return }
        guard let dictationController else { return }
        dictationController.cancelRecordingFromEscape()
    }

    private func announceStateChangeIfNeeded(_ state: DictationController.State) {
        guard previousState != state else { return }

        let announcement: String?
        switch state {
        case .idle:
            announcement = nil
        case .recording:
            announcement = localized(
                "dictation.panel.announcement.recording",
                default: "Recording started.",
                comment: "VoiceOver announcement when recording begins"
            )
        case .transcribing:
            announcement = localized(
                "dictation.panel.announcement.transcribing",
                default: "Transcribing recording.",
                comment: "VoiceOver announcement when transcription begins"
            )
        case .success:
            announcement = localized(
                "dictation.panel.announcement.success",
                default: "Dictation completed.",
                comment: "VoiceOver announcement when transcription succeeds"
            )
        case .error:
            announcement = localized(
                "dictation.panel.announcement.error",
                default: "Dictation failed.",
                comment: "VoiceOver announcement when transcription fails"
            )
        }

        guard let announcement else { return }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}
