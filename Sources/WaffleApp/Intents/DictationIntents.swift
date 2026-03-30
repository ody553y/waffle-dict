import AppIntents

@MainActor
protocol DictationIntentControlling: AnyObject {
    func handleHotkeyPress() async
}

extension DictationController: DictationIntentControlling {}

@MainActor
final class DictationIntentBridge {
    static let shared = DictationIntentBridge()

    weak var dictationController: (any DictationIntentControlling)?

    private init() {}
}

struct StartDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Dictation"
    static let description = IntentDescription("Starts a new Waffle dictation recording.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await DictationIntentBridge.shared.dictationController?.handleHotkeyPress()
        return .result()
    }
}

struct StopDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Dictation"
    static let description = IntentDescription("Stops the current Waffle dictation recording and transcribes it.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await DictationIntentBridge.shared.dictationController?.handleHotkeyPress()
        return .result()
    }
}

struct WaffleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Dictate with \(.applicationName)",
            ],
            shortTitle: "Start Dictation",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: StopDictationIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Stop dictating",
            ],
            shortTitle: "Stop Dictation",
            systemImageName: "mic.slash.fill"
        )

        AppShortcut(
            intent: GetLastTranscriptIntent(),
            phrases: [
                "Get last \(.applicationName) transcript",
            ],
            shortTitle: "Get Last Transcript",
            systemImageName: "text.quote"
        )

        AppShortcut(
            intent: SearchTranscriptsIntent(),
            phrases: [
                "Search \(.applicationName) for \(\.$query)",
            ],
            shortTitle: "Search Transcripts",
            systemImageName: "magnifyingglass"
        )
    }
}
