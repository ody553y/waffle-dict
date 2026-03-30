import AppIntents
import WaffleCore

enum TranscriptIntentError: Error, Equatable, LocalizedError, CustomLocalizedStringResourceConvertible {
    case transcriptStoreUnavailable
    case noTranscriptsFound

    var errorDescription: String? {
        switch self {
        case .transcriptStoreUnavailable:
            return "Transcript store is unavailable."
        case .noTranscriptsFound:
            return "No transcripts found."
        }
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .transcriptStoreUnavailable:
            return "Transcript store is unavailable."
        case .noTranscriptsFound:
            return "No transcripts found."
        }
    }
}

final class TranscriptIntentBridge: @unchecked Sendable {
    static let shared = TranscriptIntentBridge()

    weak var transcriptStore: TranscriptStore?

    private init() {}
}

struct GetLastTranscriptIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Last Transcript"
    static let description = IntentDescription("Returns the text of the most recent Waffle transcript.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let text = try Self.latestTranscriptText(from: TranscriptIntentBridge.shared.transcriptStore)
        return .result(value: text)
    }

    static func latestTranscriptText(from store: TranscriptStore?) throws -> String {
        guard let store else {
            throw TranscriptIntentError.transcriptStoreUnavailable
        }

        let records = try store.fetchAll(limit: 1)
        guard let latest = records.first else {
            throw TranscriptIntentError.noTranscriptsFound
        }

        return latest.text
    }
}

struct SearchTranscriptsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Transcripts"
    static let description = IntentDescription("Searches Waffle transcripts and returns matching text.")
    static let openAppWhenRun = false

    @Parameter(title: "Query", description: "The text to search for.")
    var query: String

    @Parameter(title: "Max Results", description: "Maximum number of results to return.", default: 5)
    var maxResults: Int

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let texts = try Self.searchTexts(
            query: query,
            maxResults: maxResults,
            store: TranscriptIntentBridge.shared.transcriptStore
        )
        return .result(value: texts)
    }

    static func searchTexts(query: String, maxResults: Int, store: TranscriptStore?) throws -> [String] {
        guard let store else {
            throw TranscriptIntentError.transcriptStoreUnavailable
        }

        let clamped = max(1, min(maxResults, 20))
        let records = try store.search(query: query, limit: clamped)
        return records.map(\.text)
    }
}
