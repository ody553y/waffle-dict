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
}
