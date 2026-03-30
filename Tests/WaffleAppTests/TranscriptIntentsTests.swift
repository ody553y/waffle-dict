import Foundation
import Testing
@testable import WaffleApp
@testable import WaffleCore

@Suite(.serialized)
struct TranscriptIntentsTests {
    @Test func getLastTranscriptIntentReturnsMostRecentTranscriptText() async throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        try seedTranscript(text: "older transcript", timestamp: 1_710_000_000, store: store)
        try seedTranscript(text: "latest transcript", timestamp: 1_710_000_010, store: store)
        TranscriptIntentBridge.shared.transcriptStore = store
        defer { TranscriptIntentBridge.shared.transcriptStore = nil }

        let result = try await GetLastTranscriptIntent().perform()
        #expect(result.value == "latest transcript")
    }

    @Test func getLastTranscriptIntentThrowsWhenStoreIsUnavailable() async {
        TranscriptIntentBridge.shared.transcriptStore = nil

        await #expect(throws: TranscriptIntentError.transcriptStoreUnavailable) {
            _ = try await GetLastTranscriptIntent().perform()
        }
    }

    @Test func getLastTranscriptIntentThrowsWhenNoTranscriptsExist() async throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        TranscriptIntentBridge.shared.transcriptStore = store
        defer { TranscriptIntentBridge.shared.transcriptStore = nil }

        await #expect(throws: TranscriptIntentError.noTranscriptsFound) {
            _ = try await GetLastTranscriptIntent().perform()
        }
    }

    @Test func searchTranscriptsIntentReturnsMatchingTranscriptTexts() async throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        try seedTranscript(text: "alpha one", timestamp: 1_710_000_000, store: store)
        try seedTranscript(text: "beta", timestamp: 1_710_000_005, store: store)
        try seedTranscript(text: "alpha two", timestamp: 1_710_000_010, store: store)
        TranscriptIntentBridge.shared.transcriptStore = store
        defer { TranscriptIntentBridge.shared.transcriptStore = nil }

        let intent = makeSearchIntent(query: "alpha", maxResults: 5)
        let result = try await intent.perform()

        #expect(result.value == ["alpha two", "alpha one"])
    }

    @Test func searchTranscriptsIntentClampsMaxResultsToUpperBound() async throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        for index in 0..<25 {
            try seedTranscript(
                text: "match \(index)",
                timestamp: 1_710_000_000 + TimeInterval(index),
                store: store
            )
        }
        TranscriptIntentBridge.shared.transcriptStore = store
        defer { TranscriptIntentBridge.shared.transcriptStore = nil }

        let intent = makeSearchIntent(query: "match", maxResults: 999)
        let result = try await intent.perform()

        #expect(result.value?.count == 20)
    }

    @Test func searchTranscriptsIntentClampsMaxResultsToLowerBound() async throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        try seedTranscript(text: "alpha one", timestamp: 1_710_000_000, store: store)
        try seedTranscript(text: "alpha two", timestamp: 1_710_000_010, store: store)
        TranscriptIntentBridge.shared.transcriptStore = store
        defer { TranscriptIntentBridge.shared.transcriptStore = nil }

        let intent = makeSearchIntent(query: "alpha", maxResults: 0)
        let result = try await intent.perform()

        #expect(result.value?.count == 1)
        #expect(result.value == ["alpha two"])
    }

    @Test func searchTranscriptsIntentEmptyQueryReturnsRecentTranscripts() async throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        try seedTranscript(text: "oldest", timestamp: 1_710_000_000, store: store)
        try seedTranscript(text: "middle", timestamp: 1_710_000_010, store: store)
        try seedTranscript(text: "newest", timestamp: 1_710_000_020, store: store)
        TranscriptIntentBridge.shared.transcriptStore = store
        defer { TranscriptIntentBridge.shared.transcriptStore = nil }

        let intent = makeSearchIntent(query: "", maxResults: 2)
        let result = try await intent.perform()

        #expect(result.value == ["newest", "middle"])
    }

    @Test func searchTranscriptsIntentThrowsWhenStoreIsUnavailable() async {
        TranscriptIntentBridge.shared.transcriptStore = nil

        let intent = makeSearchIntent(query: "alpha", maxResults: 5)

        await #expect(throws: TranscriptIntentError.transcriptStoreUnavailable) {
            _ = try await intent.perform()
        }
    }

    private func seedTranscript(
        text: String,
        timestamp: TimeInterval,
        store: TranscriptStore
    ) throws {
        _ = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: timestamp),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: text
            )
        )
    }

    private func makeSearchIntent(query: String, maxResults: Int) -> SearchTranscriptsIntent {
        let intent = SearchTranscriptsIntent()
        intent.query = query
        intent.maxResults = maxResults
        return intent
    }
}
