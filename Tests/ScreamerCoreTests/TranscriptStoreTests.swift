import Foundation
import Testing
@testable import ScreamerCore

@Suite(.serialized)
struct TranscriptStoreTests {
    @Test func saveAssignsIDAndFetchOneReturnsStoredRecord() throws {
        let store = try TranscriptStore(databasePath: ":memory:")

        let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
        let input = TranscriptRecord(
            createdAt: createdAt,
            sourceType: "dictation",
            sourceFileName: nil,
            modelID: "whisper-small",
            languageHint: nil,
            durationSeconds: 2.5,
            text: "hello world"
        )

        let saved = try store.save(input)
        let id = try #require(saved.id)

        #expect(id > 0)
        #expect(saved.createdAt == createdAt)
        #expect(saved.sourceType == "dictation")
        #expect(saved.modelID == "whisper-small")
        #expect(saved.text == "hello world")

        let fetched = try store.fetchOne(id: id)
        #expect(fetched == saved)
    }

    @Test func fetchAllReturnsNewestFirstWithPagination() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let base = Date(timeIntervalSince1970: 1_710_000_000)

        _ = try store.save(
            TranscriptRecord(
                createdAt: base,
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: 1,
                text: "first"
            )
        )
        _ = try store.save(
            TranscriptRecord(
                createdAt: base.addingTimeInterval(10),
                sourceType: "file_import",
                sourceFileName: "meeting.wav",
                modelID: "whisper-small",
                languageHint: "en",
                durationSeconds: 30,
                text: "second"
            )
        )
        _ = try store.save(
            TranscriptRecord(
                createdAt: base.addingTimeInterval(20),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-medium",
                languageHint: nil,
                durationSeconds: 3,
                text: "third"
            )
        )

        let firstPage = try store.fetchAll(limit: 2, offset: 0)
        #expect(firstPage.map(\.text) == ["third", "second"])

        let secondPage = try store.fetchAll(limit: 2, offset: 2)
        #expect(secondPage.map(\.text) == ["first"])
    }

    @Test func searchFindsMatchingTranscriptsUsingFTS() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let base = Date(timeIntervalSince1970: 1_710_000_000)

        _ = try store.save(
            TranscriptRecord(
                createdAt: base,
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "alpha beta gamma"
            )
        )
        _ = try store.save(
            TranscriptRecord(
                createdAt: base.addingTimeInterval(10),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "project alpha notes"
            )
        )
        _ = try store.save(
            TranscriptRecord(
                createdAt: base.addingTimeInterval(20),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "different words"
            )
        )

        let matches = try store.search(query: "alpha", limit: 10)
        #expect(matches.map(\.text) == ["project alpha notes", "alpha beta gamma"])
    }

    @Test func deleteRemovesTranscriptAndSearchEntry() throws {
        let store = try TranscriptStore(databasePath: ":memory:")

        let saved = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "delete me"
            )
        )
        let id = try #require(saved.id)

        try store.delete(id: id)

        #expect(try store.fetchOne(id: id) == nil)
        #expect(try store.search(query: "delete", limit: 10).isEmpty)
    }

    @Test func saveFetchDeleteActionsPersistsResultsNewestFirst() throws {
        let store = try TranscriptStore(databasePath: ":memory:")

        let transcript = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: 10,
                text: "action source"
            )
        )
        let transcriptID = try #require(transcript.id)

        let older = try store.saveAction(
            TranscriptActionRecord(
                transcriptID: transcriptID,
                createdAt: Date(timeIntervalSince1970: 1_710_000_010),
                actionType: "summarise",
                actionInput: nil,
                llmModelID: "qwen3-8b",
                resultText: "Older summary"
            )
        )
        let newer = try store.saveAction(
            TranscriptActionRecord(
                transcriptID: transcriptID,
                createdAt: Date(timeIntervalSince1970: 1_710_000_020),
                actionType: "question",
                actionInput: "What are the actions?",
                llmModelID: "qwen3-8b",
                resultText: "Newer answer"
            )
        )

        let actions = try store.fetchActions(forTranscriptID: transcriptID)
        #expect(actions.map(\.resultText) == ["Newer answer", "Older summary"])
        #expect(actions.map(\.actionType) == ["question", "summarise"])
        #expect(actions.first?.transcriptID == transcriptID)
        #expect(actions.first?.id == newer.id)
        #expect(actions.last?.id == older.id)

        let newerID = try #require(newer.id)
        try store.deleteAction(id: newerID)

        let remaining = try store.fetchActions(forTranscriptID: transcriptID)
        #expect(remaining.count == 1)
        #expect(remaining[0].id == older.id)
        #expect(remaining[0].resultText == "Older summary")
    }

    @Test func deletingTranscriptCascadesToTranscriptActions() throws {
        let store = try TranscriptStore(databasePath: ":memory:")

        let transcript = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: 10,
                text: "cascade source"
            )
        )
        let transcriptID = try #require(transcript.id)

        _ = try store.saveAction(
            TranscriptActionRecord(
                transcriptID: transcriptID,
                createdAt: Date(timeIntervalSince1970: 1_710_000_030),
                actionType: "custom",
                actionInput: "Extract TODOs",
                llmModelID: "qwen3-8b",
                resultText: "TODO: ship"
            )
        )
        #expect(try store.fetchActions(forTranscriptID: transcriptID).count == 1)

        try store.delete(id: transcriptID)

        #expect(try store.fetchOne(id: transcriptID) == nil)
        #expect(try store.fetchActions(forTranscriptID: transcriptID).isEmpty)
    }

    @Test func saveAndFetchRoundTripsSegments() throws {
        let store = try TranscriptStore(databasePath: ":memory:")

        let input = TranscriptRecord(
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            sourceType: "dictation",
            sourceFileName: nil,
            modelID: "whisper-small",
            languageHint: "en",
            durationSeconds: 3.0,
            text: "hello world",
            segments: [
                TranscriptSegment(start: 0.0, end: 1.0, text: "hello", speaker: "SPEAKER_00"),
                TranscriptSegment(start: 1.0, end: 2.2, text: "world", speaker: "SPEAKER_01"),
            ]
        )

        let saved = try store.save(input)
        let id = try #require(saved.id)

        let fetched = try #require(try store.fetchOne(id: id))
        #expect(fetched.segments == input.segments)
    }

    @Test func saveAndFetchHandlesNilSegments() throws {
        let store = try TranscriptStore(databasePath: ":memory:")

        let saved = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: 1.0,
                text: "no segments",
                segments: nil
            )
        )
        let id = try #require(saved.id)

        let fetched = try #require(try store.fetchOne(id: id))
        #expect(fetched.segments == nil)
    }

    @Test func transcriptSegmentJSONRoundTripsWithAndWithoutSpeaker() throws {
        let segments = [
            TranscriptSegment(start: 0.0, end: 1.0, text: "hello", speaker: "SPEAKER_00"),
            TranscriptSegment(start: 1.0, end: 2.0, text: "world", speaker: nil),
        ]

        let encoded = try JSONEncoder().encode(segments)
        let decoded = try JSONDecoder().decode([TranscriptSegment].self, from: encoded)

        #expect(decoded == segments)
    }
}
