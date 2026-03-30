import Testing
@testable import WaffleApp

@Suite(.serialized)
struct DictationIntentsTests {
    @Test @MainActor func appDelegateRegistersIntentBridgesWhenControllerIsCreated() {
        let appDelegate = AppDelegate()
        DictationIntentBridge.shared.dictationController = nil
        TranscriptIntentBridge.shared.transcriptStore = nil

        let controller = appDelegate.dictationController

        #expect((DictationIntentBridge.shared.dictationController as AnyObject?) === controller)
        #expect(TranscriptIntentBridge.shared.transcriptStore === appDelegate.transcriptStore)
    }

    @Test @MainActor func startDictationIntentCallsHandleHotkeyPress() async throws {
        let spy = DictationIntentControllerSpy()
        DictationIntentBridge.shared.dictationController = spy
        defer { DictationIntentBridge.shared.dictationController = nil }

        _ = try await StartDictationIntent().perform()

        #expect(spy.handleHotkeyPressCallCount == 1)
    }

    @Test @MainActor func stopDictationIntentCallsHandleHotkeyPress() async throws {
        let spy = DictationIntentControllerSpy()
        DictationIntentBridge.shared.dictationController = spy
        defer { DictationIntentBridge.shared.dictationController = nil }

        _ = try await StopDictationIntent().perform()

        #expect(spy.handleHotkeyPressCallCount == 1)
    }

    @Test @MainActor func dictationIntentBridgeKeepsWeakReference() {
        DictationIntentBridge.shared.dictationController = nil
        weak var weakSpy: DictationIntentControllerSpy?

        do {
            let spy = DictationIntentControllerSpy()
            weakSpy = spy
            DictationIntentBridge.shared.dictationController = spy
            #expect(DictationIntentBridge.shared.dictationController != nil)
        }

        #expect(weakSpy == nil)
        #expect(DictationIntentBridge.shared.dictationController == nil)
    }
}

@MainActor
private final class DictationIntentControllerSpy: DictationIntentControlling {
    private(set) var handleHotkeyPressCallCount = 0

    func handleHotkeyPress() async {
        handleHotkeyPressCallCount += 1
    }
}
