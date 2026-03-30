import Foundation
import Testing
@testable import WaffleCore

@Suite(.serialized)
struct TranscriptArchiverTests {
    @Test func exportImportRoundTripPreservesTranscriptsAndActions() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let recordOne = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: "en",
                durationSeconds: 120,
                text: "First transcript body",
                segments: [
                    TranscriptSegment(start: 0, end: 1, text: "hello", speaker: "SPEAKER_00"),
                ],
                speakerMap: ["SPEAKER_00": "Alice"],
                notes: "note-a",
                audioFilePath: "/tmp/audio-a.wav"
            )
        )
        let recordTwo = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_100),
                sourceType: "file_import",
                sourceFileName: "meeting.wav",
                modelID: "parakeet-0.6b",
                languageHint: nil,
                durationSeconds: 90,
                text: "Second transcript body",
                segments: nil,
                speakerMap: nil,
                notes: nil,
                audioFilePath: nil
            )
        )

        let recordOneID = try #require(recordOne.id)
        let recordTwoID = try #require(recordTwo.id)
        _ = try store.saveAction(
            TranscriptActionRecord(
                transcriptID: recordOneID,
                createdAt: Date(timeIntervalSince1970: 1_710_000_010),
                actionType: "summarise",
                actionInput: nil,
                llmModelID: "qwen3-8b",
                resultText: "Summary one"
            )
        )
        _ = try store.saveAction(
            TranscriptActionRecord(
                transcriptID: recordOneID,
                createdAt: Date(timeIntervalSince1970: 1_710_000_020),
                actionType: "auto_summarise",
                actionInput: "auto",
                llmModelID: "qwen3-8b",
                resultText: "Auto summary one"
            )
        )
        _ = try store.saveAction(
            TranscriptActionRecord(
                transcriptID: recordTwoID,
                createdAt: Date(timeIntervalSince1970: 1_710_000_030),
                actionType: "custom_prompt",
                actionInput: "Extract actions",
                llmModelID: "qwen3-8b",
                resultText: "Action list"
            )
        )

        let archiver = TranscriptArchiver(appVersionProvider: { "9.9.9" })
        let data = try archiver.export(transcripts: [recordOne, recordTwo], store: store)
        let archive = try archiver.import(from: data)

        #expect(archive.version == 1)
        #expect(archive.appVersion == "9.9.9")
        #expect(archive.transcripts.count == 2)

        let importedOne = try #require(archive.transcripts.first(where: { $0.record.id == recordOneID }))
        let importedTwo = try #require(archive.transcripts.first(where: { $0.record.id == recordTwoID }))
        #expect(importedOne.record == recordOne)
        #expect(importedTwo.record == recordTwo)
        #expect(importedOne.actions.count == 2)
        #expect(importedTwo.actions.count == 1)
        #expect(importedOne.actions.map(\.actionType) == ["auto_summarise", "summarise"])
        #expect(importedTwo.actions.map(\.actionType) == ["custom_prompt"])
    }

    @Test func writeReadRoundTripProducesValidUTF8JSON() throws {
        let archiver = TranscriptArchiver(appVersionProvider: { "1.2.3" })
        let archive = WaffleArchive(
            version: 1,
            exportedAt: Date(timeIntervalSince1970: 1_710_000_000),
            appVersion: "1.2.3",
            transcripts: []
        )
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("waffle-archive-\(UUID().uuidString).waffle")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try archiver.write(archive, to: outputURL)
        let rawData = try Data(contentsOf: outputURL)
        let jsonString = try #require(String(data: rawData, encoding: .utf8))
        let readArchive = try archiver.read(from: outputURL)

        #expect(jsonString.contains("\"version\""))
        #expect(jsonString.contains("\n"))
        #expect(readArchive == archive)
    }

    @Test func importThrowsUnsupportedVersionForFutureArchives() throws {
        let archiver = TranscriptArchiver()
        let json = """
        {
          "appVersion": "99.0.0",
          "exportedAt": "2026-03-30T00:00:00Z",
          "transcripts": [],
          "version": 2
        }
        """
        let data = Data(json.utf8)

        #expect(throws: ArchiveError.unsupportedVersion(2)) {
            _ = try archiver.import(from: data)
        }
    }

    @Test func exportIncludesEmptyActionArraysWhenNoActionsExist() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let transcript = try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: 12,
                text: "Transcript with no actions"
            )
        )

        let archiver = TranscriptArchiver(appVersionProvider: { "1.0.0" })
        let data = try archiver.export(transcripts: [transcript], store: store)
        let archive = try archiver.import(from: data)

        #expect(archive.transcripts.count == 1)
        #expect(archive.transcripts[0].actions.isEmpty)
    }
}
