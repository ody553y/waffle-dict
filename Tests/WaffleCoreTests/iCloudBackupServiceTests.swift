import Foundation
import Testing
@testable import WaffleCore

@Suite(.serialized)
struct iCloudBackupServiceTests {
    @Test func backupFilenameUsesDateAndSanitizedModelID() {
        let service = iCloudBackupService(containerURLProvider: { _, _ in nil })
        let transcript = TranscriptRecord(
            createdAt: makeUTCDate(year: 2026, month: 3, day: 30),
            sourceType: "dictation",
            sourceFileName: nil,
            modelID: "gpt 4o:mini/test",
            languageHint: nil,
            durationSeconds: nil,
            text: "hello"
        )

        let filename = service.backupFilename(for: transcript)

        #expect(filename == "2026-03-30_gpt-4o-mini-test-transcript.waffle")
    }

    @Test func backupWritesReadableArchiveIntoContainer() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = iCloudBackupService(
            containerURLProvider: { _, _ in root }
        )
        let transcript = TranscriptRecord(
            id: 42,
            createdAt: makeUTCDate(year: 2026, month: 3, day: 30),
            sourceType: "dictation",
            sourceFileName: nil,
            modelID: "whisper-small",
            languageHint: "en",
            durationSeconds: 12,
            text: "backup me"
        )
        let actions = [
            TranscriptActionRecord(
                transcriptID: 42,
                createdAt: makeUTCDate(year: 2026, month: 3, day: 30),
                actionType: "summarise",
                actionInput: nil,
                llmModelID: "qwen3-8b",
                resultText: "summary"
            ),
        ]

        try service.backup(transcript: transcript, actions: actions)
        let backupURLs = try service.listBackups()
        let archive = try TranscriptArchiver().read(from: try #require(backupURLs.first))

        #expect(backupURLs.count == 1)
        #expect(archive.transcripts.count == 1)
        #expect(archive.transcripts[0].record == transcript)
        #expect(archive.transcripts[0].actions == actions)
    }

    @Test func listBackupsReturnsOnlyScreamFilesSortedNewestFirst() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let backupsDirectory = root
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

        let oldFile = backupsDirectory.appendingPathComponent("old.waffle")
        let newFile = backupsDirectory.appendingPathComponent("new.waffle")
        let ignoredFile = backupsDirectory.appendingPathComponent("ignore.txt")
        try Data("old".utf8).write(to: oldFile)
        try Data("new".utf8).write(to: newFile)
        try Data("ignore".utf8).write(to: ignoredFile)
        try FileManager.default.setAttributes(
            [.modificationDate: makeUTCDate(year: 2026, month: 3, day: 29)],
            ofItemAtPath: oldFile.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: makeUTCDate(year: 2026, month: 3, day: 30)],
            ofItemAtPath: newFile.path
        )

        let service = iCloudBackupService(containerURLProvider: { _, _ in root })
        let backupURLs = try service.listBackups()

        #expect(backupURLs.map(\.lastPathComponent) == ["new.waffle", "old.waffle"])
    }

    @Test func backupIsNoOpWhenContainerIsUnavailable() throws {
        let service = iCloudBackupService(containerURLProvider: { _, _ in nil })
        let transcript = TranscriptRecord(
            createdAt: makeUTCDate(year: 2026, month: 3, day: 30),
            sourceType: "dictation",
            sourceFileName: nil,
            modelID: "whisper-small",
            languageHint: nil,
            durationSeconds: nil,
            text: "no backup"
        )

        try service.backup(transcript: transcript, actions: [])
        let backups = try service.listBackups()

        #expect(backups.isEmpty)
    }

    @Test func deleteBackupRemovesFileFromContainer() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let backupsDirectory = root
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let backupURL = backupsDirectory.appendingPathComponent("delete-me.waffle")
        try Data("delete".utf8).write(to: backupURL)

        let service = iCloudBackupService(containerURLProvider: { _, _ in root })
        try service.deleteBackup(at: backupURL)

        #expect(FileManager.default.fileExists(atPath: backupURL.path) == false)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeUTCDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    return components.date ?? Date(timeIntervalSince1970: 0)
}
