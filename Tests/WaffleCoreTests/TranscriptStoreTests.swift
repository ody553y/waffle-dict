import Foundation
import GRDB
import Testing
@testable import WaffleCore

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

    @Test func updateSegmentsUpdatesSegmentsAndDerivedTextAtomically() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let saved = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: "en",
                durationSeconds: 9.0,
                text: "old text",
                segments: [
                    TranscriptSegment(start: 0.0, end: 1.0, text: "old", speaker: "SPEAKER_00"),
                ]
            )
        )
        let id = try #require(saved.id)

        let updatedSegments = [
            TranscriptSegment(start: 0.0, end: 1.2, text: "hello", speaker: "SPEAKER_00"),
            TranscriptSegment(start: 1.2, end: 2.4, text: "world", speaker: "SPEAKER_01"),
            TranscriptSegment(start: 2.4, end: 3.0, text: "again", speaker: nil),
        ]

        try store.updateSegments(id: id, segments: updatedSegments)

        let updated = try #require(try store.fetchOne(id: id))
        #expect(updated.segments == updatedSegments)
        #expect(updated.text == "hello world again")
        #expect(updated.modelID == "whisper-small")
        #expect(updated.createdAt == saved.createdAt)
        #expect(updated.durationSeconds == saved.durationSeconds)
    }

    @Test func updateTextUpdatesOnlyTextColumn() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let originalSegments = [
            TranscriptSegment(start: 0.0, end: 1.0, text: "hello", speaker: "SPEAKER_00"),
            TranscriptSegment(start: 1.0, end: 2.0, text: "world", speaker: nil),
        ]
        let saved = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "file_import",
                sourceFileName: "meeting.wav",
                modelID: "whisper-medium",
                languageHint: "en",
                durationSeconds: 42.0,
                text: "before update",
                segments: originalSegments
            )
        )
        let id = try #require(saved.id)

        try store.updateText(id: id, text: "after update")

        let updated = try #require(try store.fetchOne(id: id))
        #expect(updated.text == "after update")
        #expect(updated.segments == originalSegments)
        #expect(updated.modelID == "whisper-medium")
        #expect(updated.sourceFileName == "meeting.wav")
    }

    @Test func updateSegmentsAndUpdateTextThrowForMissingRecordID() throws {
        let store = try TranscriptStore(databasePath: ":memory:")

        #expect(throws: Error.self) {
            try store.updateSegments(
                id: 999,
                segments: [TranscriptSegment(start: 0.0, end: 1.0, text: "test", speaker: nil)]
            )
        }

        #expect(throws: Error.self) {
            try store.updateText(id: 999, text: "test")
        }
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
            notes: "Follow up on TODOs",
            audioFilePath: "/tmp/audio.wav"
        )

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TranscriptRecord.self, from: encoded)

        #expect(decoded.speakerMap == ["SPEAKER_00": "Alice"])
        #expect(decoded.notes == "Follow up on TODOs")
        #expect(decoded.audioFilePath == "/tmp/audio.wav")
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

    @Test func updateAudioFilePathRoundTripsAndClears() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let saved = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "audio linked transcript"
            )
        )
        let id = try #require(saved.id)

        try store.updateAudioFilePath(id: id, path: "/tmp/retained.wav")
        let updated = try #require(try store.fetchOne(id: id))
        #expect(updated.audioFilePath == "/tmp/retained.wav")

        try store.updateAudioFilePath(id: id, path: nil)
        let cleared = try #require(try store.fetchOne(id: id))
        #expect(cleared.audioFilePath == nil)
    }

    @Test func fetchUnreviewedReturnsOnlyNilStatusNewestFirst() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let base = Date(timeIntervalSince1970: 1_710_000_000)

        let first = try store.save(
            TranscriptRecord(
                createdAt: base,
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "first unreviewed"
            )
        )
        var approved = try store.save(
            TranscriptRecord(
                createdAt: base.addingTimeInterval(1),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "approved"
            )
        )
        var dismissed = try store.save(
            TranscriptRecord(
                createdAt: base.addingTimeInterval(2),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "dismissed"
            )
        )
        let newest = try store.save(
            TranscriptRecord(
                createdAt: base.addingTimeInterval(3),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "newest unreviewed"
            )
        )

        approved.reviewStatus = ReviewStatus.approved
        dismissed.reviewStatus = ReviewStatus.dismissed
        try store.setReviewStatus(id: try #require(approved.id), status: approved.reviewStatus)
        try store.setReviewStatus(id: try #require(dismissed.id), status: dismissed.reviewStatus)

        let unreviewed = try store.fetchUnreviewed(limit: 10)
        #expect(unreviewed.map(\.text) == ["newest unreviewed", "first unreviewed"])
        #expect(unreviewed.map(\.reviewStatus) == [nil, nil])
        #expect(unreviewed.map(\.id) == [newest.id, first.id])
    }

    @Test func setReviewStatusPersistsAndCanResetToUnreviewed() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let saved = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "status target"
            )
        )
        let id = try #require(saved.id)

        try store.setReviewStatus(id: id, status: ReviewStatus.approved)
        let approved = try #require(try store.fetchOne(id: id))
        #expect(approved.reviewStatus == ReviewStatus.approved)

        try store.setReviewStatus(id: id, status: nil)
        let reset = try #require(try store.fetchOne(id: id))
        #expect(reset.reviewStatus == nil)
    }

    @Test func unreviewedCountExcludesApprovedAndDismissed() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let first = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "unreviewed 1"
            )
        )
        let second = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_001),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "unreviewed 2"
            )
        )
        let third = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_002),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: "approved"
            )
        )

        try store.setReviewStatus(id: try #require(third.id), status: ReviewStatus.approved)
        #expect(try store.unreviewedCount() == 2)

        try store.setReviewStatus(id: try #require(first.id), status: ReviewStatus.dismissed)
        #expect(try store.unreviewedCount() == 1)

        try store.setReviewStatus(id: try #require(second.id), status: ReviewStatus.approved)
        #expect(try store.unreviewedCount() == 0)
    }

    @Test func saveAndFetchSpeakerEmbeddingsRoundTrip() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let transcript = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "file_import",
                sourceFileName: "meeting.wav",
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: 30,
                text: "hello"
            )
        )
        let transcriptID = try #require(transcript.id)

        let embeddings: [String: [Float]] = [
            "SPEAKER_00": [0.1, 0.2, 0.3],
            "SPEAKER_01": [0.4, 0.5, 0.6],
        ]

        try store.saveEmbeddings(embeddings, transcriptID: transcriptID)
        let fetched = try store.fetchEmbeddings(transcriptID: transcriptID)

        #expect(fetched["SPEAKER_00"] == [0.1, 0.2, 0.3])
        #expect(fetched["SPEAKER_01"] == [0.4, 0.5, 0.6])
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

    @Test func migrationFromLegacySchemaAddsSpeakerMapNotesAudioPathAndEmbeddingTables() throws {
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
        #expect(columnNames.contains("audioFilePath"))
        #expect(columnNames.contains("reviewStatus"))

        let tableNames = try legacyQueue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        #expect(tableNames.contains("speaker_profiles"))
        #expect(tableNames.contains("transcript_speaker_embeddings"))

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

    @Test func migrationAddsReviewStatusColumnWithoutDataLoss() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptStoreReviewStatusMigration-\(UUID().uuidString)", isDirectory: true)
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
                table.column("speakerMap", .text)
                table.column("notes", .text)
                table.column("audioFilePath", .text)
            }

            try db.create(index: "idx_transcripts_createdAt", on: "transcripts", columns: ["createdAt"])

            try db.create(virtualTable: "transcripts_fts", using: FTS5()) { table in
                table.column("text")
                table.column("notes")
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

            try db.create(table: "speaker_profiles") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("displayName", .text).notNull()
                table.column("createdAt", .double).notNull()
                table.column("lastSeenAt", .double).notNull()
                table.column("averageEmbedding", .blob).notNull()
                table.column("transcriptCount", .integer).notNull().defaults(to: 1)
            }

            try db.create(table: "transcript_speaker_embeddings") { table in
                table.column("transcriptID", .integer)
                    .notNull()
                    .references("transcripts", onDelete: .cascade)
                table.column("speakerLabel", .text).notNull()
                table.column("embedding", .blob).notNull()
                table.primaryKey(["transcriptID", "speakerLabel"])
            }

            try db.create(
                index: "idx_transcript_speaker_embeddings_transcriptID",
                on: "transcript_speaker_embeddings",
                columns: ["transcriptID"]
            )

            try db.create(table: "grdb_migrations") { table in
                table.column("identifier", .text).notNull().primaryKey()
            }
            try db.execute(
                sql: """
                INSERT INTO grdb_migrations(identifier)
                VALUES
                    ('createTranscripts'),
                    ('createTranscriptActions'),
                    ('addSegmentsColumn'),
                    ('addSpeakerMapColumn'),
                    ('addNotesColumn'),
                    ('addAudioFilePathColumn'),
                    ('createSpeakerProfiles'),
                    ('createTranscriptSpeakerEmbeddings'),
                    ('rebuildTranscriptsFTSWithNotes')
                """
            )

            try db.execute(
                sql: """
                INSERT INTO transcripts(createdAt, sourceType, sourceFileName, modelID, languageHint, durationSeconds, text, segments, speakerMap, notes, audioFilePath)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    Date(timeIntervalSince1970: 1_710_000_000),
                    "dictation",
                    nil,
                    "whisper-small",
                    nil,
                    12.5,
                    "legacy transcript row",
                    nil,
                    nil,
                    "legacy notes",
                    nil,
                ]
            )
            try db.execute(
                sql: "INSERT INTO transcripts_fts(rowid, text, notes) VALUES (1, ?, ?)",
                arguments: ["legacy transcript row", "legacy notes"]
            )
        }

        let store = try TranscriptStore(databasePath: databasePath)
        let all = try store.fetchAll(limit: 10)
        #expect(all.count == 1)
        #expect(all[0].text == "legacy transcript row")
        #expect(all[0].reviewStatus == nil)
    }

    @Test func importArchiveInsertsTranscriptsAndActionsWithFreshIDs() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let archive = WaffleArchive(
            version: 1,
            exportedAt: Date(timeIntervalSince1970: 1_710_000_000),
            appVersion: "1.0.0",
            transcripts: [
                ArchivedTranscript(
                    record: TranscriptRecord(
                        id: 99,
                        createdAt: Date(timeIntervalSince1970: 1_710_000_001),
                        sourceType: "dictation",
                        sourceFileName: nil,
                        modelID: "whisper-small",
                        languageHint: "en",
                        durationSeconds: 11,
                        text: "Imported transcript text",
                        segments: [
                            TranscriptSegment(start: 0, end: 1, text: "hello", speaker: "SPEAKER_00"),
                        ],
                        speakerMap: ["SPEAKER_00": "Alice"],
                        notes: "note"
                    ),
                    actions: [
                        TranscriptActionRecord(
                            id: 88,
                            transcriptID: 99,
                            createdAt: Date(timeIntervalSince1970: 1_710_000_002),
                            actionType: "auto_summarise",
                            actionInput: "prompt",
                            llmModelID: "qwen3-8b",
                            resultText: "Summary"
                        ),
                    ]
                ),
            ]
        )

        let result = try store.importArchive(archive)
        let importedID = try #require(result.firstImportedTranscriptID)
        #expect(result.importedTranscriptCount == 1)
        #expect(result.importedActionCount == 1)
        #expect(result.skippedDuplicateCount == 0)
        #expect(importedID != 99)

        let importedRecord = try #require(try store.fetchOne(id: importedID))
        #expect(importedRecord.text == "Imported transcript text")
        #expect(importedRecord.speakerMap == ["SPEAKER_00": "Alice"])

        let importedActions = try store.fetchActions(forTranscriptID: importedID)
        #expect(importedActions.count == 1)
        #expect(importedActions[0].transcriptID == importedID)
        #expect(importedActions[0].resultText == "Summary")
    }

    @Test func importArchiveSkipsDuplicateMatchingCreatedAtModelAndTextPrefix() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let sharedPrefix = String(repeating: "A", count: 200)
        _ = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_010.8),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: 5,
                text: "\(sharedPrefix)-existing-tail"
            )
        )

        let archive = WaffleArchive(
            version: 1,
            exportedAt: Date(timeIntervalSince1970: 1_710_000_100),
            appVersion: "1.0.0",
            transcripts: [
                ArchivedTranscript(
                    record: TranscriptRecord(
                        id: 123,
                        createdAt: Date(timeIntervalSince1970: 1_710_000_010.2),
                        sourceType: "dictation",
                        sourceFileName: nil,
                        modelID: "whisper-small",
                        languageHint: nil,
                        durationSeconds: 5,
                        text: "\(sharedPrefix)-archive-tail"
                    ),
                    actions: []
                ),
            ]
        )

        let result = try store.importArchive(archive)

        #expect(result.importedTranscriptCount == 0)
        #expect(result.importedActionCount == 0)
        #expect(result.skippedDuplicateCount == 1)
        #expect(result.firstImportedTranscriptID == nil)
        #expect(try store.fetchAll(limit: 10).count == 1)
    }

    @Test func importArchiveRollsBackAllWritesWhenAnyRecordIsInvalid() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let archive = WaffleArchive(
            version: 1,
            exportedAt: Date(timeIntervalSince1970: 1_710_000_200),
            appVersion: "1.0.0",
            transcripts: [
                ArchivedTranscript(
                    record: TranscriptRecord(
                        id: 1,
                        createdAt: Date(timeIntervalSince1970: 1_710_000_201),
                        sourceType: "dictation",
                        sourceFileName: nil,
                        modelID: "whisper-small",
                        languageHint: nil,
                        durationSeconds: 1,
                        text: "First valid record"
                    ),
                    actions: [
                        TranscriptActionRecord(
                            id: 1,
                            transcriptID: 1,
                            createdAt: Date(timeIntervalSince1970: 1_710_000_202),
                            actionType: "summarise",
                            actionInput: nil,
                            llmModelID: "qwen3-8b",
                            resultText: "summary"
                        ),
                    ]
                ),
                ArchivedTranscript(
                    record: TranscriptRecord(
                        id: 2,
                        createdAt: Date(timeIntervalSince1970: 1_710_000_203),
                        sourceType: "dictation",
                        sourceFileName: nil,
                        modelID: "whisper-small",
                        languageHint: nil,
                        durationSeconds: 1,
                        text: "   "
                    ),
                    actions: []
                ),
            ]
        )

        #expect(throws: ArchiveError.invalidData("Transcript text cannot be empty.")) {
            _ = try store.importArchive(archive)
        }

        #expect(try store.fetchAll(limit: 10).isEmpty)
        let actionCount = try store.databaseQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_actions") ?? 0
        }
        #expect(actionCount == 0)
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

    @Test func statisticsReturnsExpectedCountsDurationsWordTotalsAndModelBreakdown() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let now = Date()

        _ = try store.save(
            TranscriptRecord(
                createdAt: now.addingTimeInterval(-100),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "model-a",
                languageHint: nil,
                durationSeconds: 30,
                text: "hello world"
            )
        )
        _ = try store.save(
            TranscriptRecord(
                createdAt: now.addingTimeInterval(-200),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "model-a",
                languageHint: nil,
                durationSeconds: nil,
                text: "another sample"
            )
        )
        _ = try store.save(
            TranscriptRecord(
                createdAt: now.addingTimeInterval(-300),
                sourceType: "file_import",
                sourceFileName: "meeting.wav",
                modelID: "model-b",
                languageHint: nil,
                durationSeconds: 90,
                text: "final transcript line"
            )
        )

        let stats = try store.statistics()

        #expect(stats.transcriptCount == 3)
        #expect(stats.totalWords == 7)
        #expect(stats.totalDurationSeconds == 120)
        #expect(stats.averageDurationSeconds == 40)
        #expect(stats.byModel["model-a"] == 2)
        #expect(stats.byModel["model-b"] == 1)
    }

    @Test func statisticsDailyCountsIncludesRecentDaysAndExcludesOlderThanThirtyDays() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let now = Date()
        let recentDate = now.addingTimeInterval(-2 * 86_400)
        let oldDate = now.addingTimeInterval(-40 * 86_400)

        _ = try store.save(
            TranscriptRecord(
                createdAt: recentDate,
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "model-a",
                languageHint: nil,
                durationSeconds: 10,
                text: "recent sample"
            )
        )
        _ = try store.save(
            TranscriptRecord(
                createdAt: oldDate,
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "model-a",
                languageHint: nil,
                durationSeconds: 10,
                text: "old sample"
            )
        )

        let stats = try store.statistics()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        let recentKey = formatter.string(from: recentDate)
        let oldKey = formatter.string(from: oldDate)

        #expect(stats.dailyCounts[recentKey] == 1)
        #expect(stats.dailyCounts[oldKey] == nil)
    }

    @Test func statisticsReturnsZeroAverageWhenNoTranscriptsExist() throws {
        let store = try TranscriptStore(databasePath: ":memory:")

        let stats = try store.statistics()

        #expect(stats.transcriptCount == 0)
        #expect(stats.totalWords == 0)
        #expect(stats.totalDurationSeconds == 0)
        #expect(stats.averageDurationSeconds == 0)
        #expect(stats.byModel.isEmpty)
    }
}
