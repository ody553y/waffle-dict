import Foundation
import GRDB
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

    @Test func transcriptRecordJSONRoundTripsSpeakerMapAndNotes() throws {
        let record = TranscriptRecord(
            id: 7,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            sourceType: "dictation",
            sourceFileName: nil,
            modelID: "whisper-small",
            languageHint: "en",
            durationSeconds: 12.0,
            text: "hello world",
            segments: [
                TranscriptSegment(start: 0.0, end: 1.0, text: "hello", speaker: "SPEAKER_00"),
            ],
            speakerMap: ["SPEAKER_00": "Alice"],
            notes: "Follow up on TODOs"
        )

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TranscriptRecord.self, from: encoded)

        #expect(decoded.speakerMap == ["SPEAKER_00": "Alice"])
        #expect(decoded.notes == "Follow up on TODOs")
    }

    @Test func resolvedSpeakerUsesMappedValueThenFallsBackToRawSpeaker() {
        let segment = TranscriptSegment(start: 0.0, end: 1.0, text: "hello", speaker: "SPEAKER_00")
        let mappedRecord = TranscriptRecord(
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            sourceType: "dictation",
            sourceFileName: nil,
            modelID: "whisper-small",
            languageHint: nil,
            durationSeconds: nil,
            text: "hello",
            segments: [segment],
            speakerMap: ["SPEAKER_00": "Alice"],
            notes: nil
        )
        let fallbackRecord = TranscriptRecord(
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            sourceType: "dictation",
            sourceFileName: nil,
            modelID: "whisper-small",
            languageHint: nil,
            durationSeconds: nil,
            text: "hello",
            segments: [segment],
            speakerMap: nil,
            notes: nil
        )

        #expect(mappedRecord.resolvedSpeaker(for: segment) == "Alice")
        #expect(fallbackRecord.resolvedSpeaker(for: segment) == "SPEAKER_00")
        #expect(fallbackRecord.resolvedSpeaker(for: TranscriptSegment(start: 0.0, end: 1.0, text: "hi", speaker: nil)) == nil)
    }

    @Test func updateSpeakerMapRoundTripsAndClears() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let saved = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: 10.0,
                text: "hello world",
                segments: [TranscriptSegment(start: 0.0, end: 1.0, text: "hello", speaker: "SPEAKER_00")]
            )
        )
        let id = try #require(saved.id)

        try store.updateSpeakerMap(id: id, speakerMap: ["SPEAKER_00": "Alice"])
        let renamed = try #require(try store.fetchOne(id: id))
        #expect(renamed.speakerMap == ["SPEAKER_00": "Alice"])
        #expect(
            renamed.resolvedSpeaker(
                for: TranscriptSegment(start: 0.0, end: 1.0, text: "hello", speaker: "SPEAKER_00")
            ) == "Alice"
        )

        try store.updateSpeakerMap(id: id, speakerMap: nil)
        let reset = try #require(try store.fetchOne(id: id))
        #expect(reset.speakerMap == nil)
    }

    @Test func updateNotesPersistsAndSearchMatchesNotes() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let saved = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "meeting transcript body"
            )
        )
        let id = try #require(saved.id)

        try store.updateNotes(id: id, notes: "Action items: send follow-up email")
        let updated = try #require(try store.fetchOne(id: id))
        #expect(updated.notes == "Action items: send follow-up email")

        let matches = try store.search(query: "follow-up", limit: 10)
        #expect(matches.map(\.id).contains(id))

        try store.updateNotes(id: id, notes: nil)
        let cleared = try #require(try store.fetchOne(id: id))
        #expect(cleared.notes == nil)
    }

    @Test func countActionsForTranscriptIDsReturnsCascadeDeleteCount() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let first = try #require(
            try store.save(
                TranscriptRecord(
                    createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                    sourceType: "dictation",
                    sourceFileName: nil,
                    modelID: "whisper-small",
                    languageHint: nil,
                    durationSeconds: nil,
                    text: "first"
                )
            ).id
        )
        let second = try #require(
            try store.save(
                TranscriptRecord(
                    createdAt: Date(timeIntervalSince1970: 1_710_000_001),
                    sourceType: "dictation",
                    sourceFileName: nil,
                    modelID: "whisper-small",
                    languageHint: nil,
                    durationSeconds: nil,
                    text: "second"
                )
            ).id
        )

        _ = try store.saveAction(
            TranscriptActionRecord(
                transcriptID: first,
                createdAt: Date(timeIntervalSince1970: 1_710_000_010),
                actionType: "summarise",
                actionInput: nil,
                llmModelID: "qwen3-8b",
                resultText: "one"
            )
        )
        _ = try store.saveAction(
            TranscriptActionRecord(
                transcriptID: first,
                createdAt: Date(timeIntervalSince1970: 1_710_000_011),
                actionType: "translate",
                actionInput: "English",
                llmModelID: "qwen3-8b",
                resultText: "two"
            )
        )
        _ = try store.saveAction(
            TranscriptActionRecord(
                transcriptID: second,
                createdAt: Date(timeIntervalSince1970: 1_710_000_012),
                actionType: "custom",
                actionInput: "Extract TODOs",
                llmModelID: "qwen3-8b",
                resultText: "three"
            )
        )

        #expect(try store.countActions(forTranscriptIDs: [first]) == 2)
        #expect(try store.countActions(forTranscriptIDs: [first, second]) == 3)
        #expect(try store.countActions(forTranscriptIDs: []) == 0)
    }

    @Test func migrationFromLegacySchemaAddsSpeakerMapAndNotesColumns() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptStoreLegacyMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databasePath = temporaryDirectory.appendingPathComponent("legacy.sqlite").path
        let legacyQueue = try DatabaseQueue(path: databasePath)
        try legacyQueue.write { db in
            try db.create(table: "transcripts") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("createdAt", .datetime).notNull()
                table.column("sourceType", .text).notNull()
                table.column("sourceFileName", .text)
                table.column("modelID", .text).notNull()
                table.column("languageHint", .text)
                table.column("durationSeconds", .double)
                table.column("text", .text).notNull()
                table.column("segments", .text)
            }

            try db.create(virtualTable: "transcripts_fts", using: FTS5()) { table in
                table.column("text")
            }

            try db.create(table: "transcript_actions") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("transcriptID", .integer)
                    .notNull()
                    .references("transcripts", onDelete: .cascade)
                table.column("createdAt", .datetime).notNull()
                table.column("actionType", .text).notNull()
                table.column("actionInput", .text)
                table.column("llmModelID", .text).notNull()
                table.column("resultText", .text).notNull()
            }

            try db.create(table: "grdb_migrations") { table in
                table.column("identifier", .text).notNull().primaryKey()
            }
            try db.execute(
                sql: """
                INSERT INTO grdb_migrations(identifier)
                VALUES
                    ('createTranscripts'),
                    ('createTranscriptActions'),
                    ('addSegmentsColumn')
                """
            )
        }

        let store = try TranscriptStore(databasePath: databasePath)

        let columnNames = try legacyQueue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(transcripts)")
                .compactMap { row in row["name"] as String? }
        }
        #expect(columnNames.contains("speakerMap"))
        #expect(columnNames.contains("notes"))

        let saved = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "legacy row"
            )
        )
        let id = try #require(saved.id)
        try store.updateNotes(id: id, notes: "legacy-note-match")
        let matches = try store.search(query: "legacy-note-match", limit: 10)
        #expect(matches.map(\.id).contains(id))
    }

    @Test func fetchFilteredComposesTextDateSourceModelAndSpeakerFilters() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let base = Date(timeIntervalSince1970: 1_710_000_000)

        _ = try store.save(
            TranscriptRecord(
                createdAt: base,
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: 60,
                text: "weekly meeting summary",
                segments: [
                    TranscriptSegment(start: 0, end: 1, text: "hello", speaker: "SPEAKER_00"),
                ]
            )
        )

        _ = try store.save(
            TranscriptRecord(
                createdAt: base.addingTimeInterval(3_600),
                sourceType: "file_import",
                sourceFileName: "planning.wav",
                modelID: "whisper-medium",
                languageHint: nil,
                durationSeconds: 120,
                text: "weekly meeting action items",
                segments: nil
            )
        )

        _ = try store.save(
            TranscriptRecord(
                createdAt: base.addingTimeInterval(7_200),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: 20,
                text: "shopping list",
                segments: nil
            )
        )

        let filter = TranscriptFilter(
            searchText: "meeting",
            dateFrom: base.addingTimeInterval(1_000),
            dateTo: base.addingTimeInterval(5_000),
            sourceType: "file_import",
            modelID: "whisper-medium",
            hasSpeakers: false
        )
        let matches = try store.fetchFiltered(filter, limit: 20, offset: 0)

        #expect(matches.count == 1)
        #expect(matches.first?.text == "weekly meeting action items")
    }

    @Test func fetchFilteredHasSpeakersOnlyReturnsSpeakerTaggedTranscripts() throws {
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
                text: "with speakers",
                segments: [
                    TranscriptSegment(start: 0, end: 1, text: "hello", speaker: "SPEAKER_00"),
                ]
            )
        )
        _ = try store.save(
            TranscriptRecord(
                createdAt: base.addingTimeInterval(1),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "without speakers",
                segments: [
                    TranscriptSegment(start: 0, end: 1, text: "hello", speaker: nil),
                ]
            )
        )

        let matches = try store.fetchFiltered(
            TranscriptFilter(hasSpeakers: true),
            limit: 10,
            offset: 0
        )

        #expect(matches.map(\.text) == ["with speakers"])
    }

    @Test func fetchDistinctModelIDsReturnsSortedUniqueValues() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let base = Date(timeIntervalSince1970: 1_710_000_000)

        _ = try store.save(
            TranscriptRecord(
                createdAt: base,
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-large",
                languageHint: nil,
                durationSeconds: nil,
                text: "one"
            )
        )
        _ = try store.save(
            TranscriptRecord(
                createdAt: base.addingTimeInterval(1),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "two"
            )
        )
        _ = try store.save(
            TranscriptRecord(
                createdAt: base.addingTimeInterval(2),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "three"
            )
        )

        let modelIDs = try store.fetchDistinctModelIDs()
        #expect(modelIDs == ["whisper-large", "whisper-small"])
    }
}
