import Foundation
import GRDB

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct TranscriptRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Identifiable, Sendable {
    public static let databaseTableName = "transcripts"

    public var id: Int64?
    public var createdAt: Date
    public var sourceType: String
    public var sourceFileName: String?
    public var modelID: String
    public var languageHint: String?
    public var durationSeconds: Double?
    public var text: String
    public var segments: [TranscriptSegment]?

    public init(
        id: Int64? = nil,
        createdAt: Date,
        sourceType: String,
        sourceFileName: String?,
        modelID: String,
        languageHint: String?,
        durationSeconds: Double?,
        text: String,
        segments: [TranscriptSegment]? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceType = sourceType
        self.sourceFileName = sourceFileName
        self.modelID = modelID
        self.languageHint = languageHint
        self.durationSeconds = durationSeconds
        self.text = text
        self.segments = segments
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case sourceType
        case sourceFileName
        case modelID
        case languageHint
        case durationSeconds
        case text
        case segments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceType = try container.decode(String.self, forKey: .sourceType)
        sourceFileName = try container.decodeIfPresent(String.self, forKey: .sourceFileName)
        modelID = try container.decode(String.self, forKey: .modelID)
        languageHint = try container.decodeIfPresent(String.self, forKey: .languageHint)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        text = try container.decode(String.self, forKey: .text)

        if let segmentsJSONString = try container.decodeIfPresent(String.self, forKey: .segments),
           segmentsJSONString.isEmpty == false {
            let data = Data(segmentsJSONString.utf8)
            segments = try JSONDecoder().decode([TranscriptSegment].self, from: data)
        } else {
            segments = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(sourceType, forKey: .sourceType)
        try container.encodeIfPresent(sourceFileName, forKey: .sourceFileName)
        try container.encode(modelID, forKey: .modelID)
        try container.encodeIfPresent(languageHint, forKey: .languageHint)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encode(text, forKey: .text)

        if let segments {
            let data = try JSONEncoder().encode(segments)
            let jsonString = String(decoding: data, as: UTF8.self)
            try container.encode(jsonString, forKey: .segments)
        } else {
            try container.encodeNil(forKey: .segments)
        }
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct TranscriptActionRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable, Identifiable, Sendable {
    public static let databaseTableName = "transcript_actions"

    public var id: Int64?
    public var transcriptID: Int64
    public var createdAt: Date
    public var actionType: String
    public var actionInput: String?
    public var llmModelID: String
    public var resultText: String

    public init(
        id: Int64? = nil,
        transcriptID: Int64,
        createdAt: Date,
        actionType: String,
        actionInput: String?,
        llmModelID: String,
        resultText: String
    ) {
        self.id = id
        self.transcriptID = transcriptID
        self.createdAt = createdAt
        self.actionType = actionType
        self.actionInput = actionInput
        self.llmModelID = llmModelID
        self.resultText = resultText
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public enum TranscriptStoreError: Error {
    case insertedRecordMissingID
}

public final class TranscriptStore: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(databasePath: String? = nil, fileManager: FileManager = .default) throws {
        let path = databasePath ?? Self.defaultDatabasePath(fileManager: fileManager)

        if path != ":memory:" {
            try Self.ensureParentDirectoryExists(forDatabasePath: path, fileManager: fileManager)
        }

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true

        dbQueue = try DatabaseQueue(path: path, configuration: configuration)
        try Self.makeMigrator().migrate(dbQueue)
    }

    public func save(_ record: TranscriptRecord) throws -> TranscriptRecord {
        var savedRecord = record
        savedRecord.id = nil

        try dbQueue.write { db in
            try savedRecord.insert(db)

            guard let id = savedRecord.id else {
                throw TranscriptStoreError.insertedRecordMissingID
            }

            try db.execute(
                sql: "INSERT INTO transcripts_fts(rowid, text) VALUES (?, ?)",
                arguments: [id, savedRecord.text]
            )
        }

        return savedRecord
    }

    public func fetchAll(limit: Int, offset: Int = 0) throws -> [TranscriptRecord] {
        try dbQueue.read { db in
            try TranscriptRecord.fetchAll(
                db,
                sql: """
                SELECT id, createdAt, sourceType, sourceFileName, modelID, languageHint, durationSeconds, text, segments
                FROM transcripts
                ORDER BY createdAt DESC, id DESC
                LIMIT ? OFFSET ?
                """,
                arguments: [max(limit, 0), max(offset, 0)]
            )
        }
    }

    public func search(query: String, limit: Int) throws -> [TranscriptRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try fetchAll(limit: limit, offset: 0)
        }

        let matchQuery = Self.makeFTSMatchQuery(from: trimmed)

        return try dbQueue.read { db in
            try TranscriptRecord.fetchAll(
                db,
                sql: """
                SELECT t.id, t.createdAt, t.sourceType, t.sourceFileName, t.modelID, t.languageHint, t.durationSeconds, t.text, t.segments
                FROM transcripts AS t
                JOIN transcripts_fts ON transcripts_fts.rowid = t.id
                WHERE transcripts_fts MATCH ?
                ORDER BY t.createdAt DESC, t.id DESC
                LIMIT ?
                """,
                arguments: [matchQuery, max(limit, 0)]
            )
        }
    }

    public func delete(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM transcripts WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM transcripts_fts WHERE rowid = ?", arguments: [id])
        }
    }

    public func fetchOne(id: Int64) throws -> TranscriptRecord? {
        try dbQueue.read { db in
            try TranscriptRecord.fetchOne(db, key: id)
        }
    }

    public func saveAction(_ record: TranscriptActionRecord) throws -> TranscriptActionRecord {
        var savedRecord = record
        savedRecord.id = nil

        try dbQueue.write { db in
            try savedRecord.insert(db)

            guard savedRecord.id != nil else {
                throw TranscriptStoreError.insertedRecordMissingID
            }
        }

        return savedRecord
    }

    public func fetchActions(forTranscriptID transcriptID: Int64) throws -> [TranscriptActionRecord] {
        try dbQueue.read { db in
            try TranscriptActionRecord.fetchAll(
                db,
                sql: """
                SELECT id, transcriptID, createdAt, actionType, actionInput, llmModelID, resultText
                FROM transcript_actions
                WHERE transcriptID = ?
                ORDER BY createdAt DESC, id DESC
                """,
                arguments: [transcriptID]
            )
        }
    }

    public func deleteAction(id: Int64) throws {
        try dbQueue.write { db in
            _ = try TranscriptActionRecord.deleteOne(db, key: id)
        }
    }

    public static func defaultDatabasePath(fileManager: FileManager = .default) -> String {
        defaultDatabaseURL(fileManager: fileManager).path
    }
}

private extension TranscriptStore {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createTranscripts") { db in
            try db.create(table: TranscriptRecord.databaseTableName) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("createdAt", .datetime).notNull()
                table.column("sourceType", .text).notNull()
                table.column("sourceFileName", .text)
                table.column("modelID", .text).notNull()
                table.column("languageHint", .text)
                table.column("durationSeconds", .double)
                table.column("text", .text).notNull()
            }

            try db.create(index: "idx_transcripts_createdAt", on: "transcripts", columns: ["createdAt"])

            try db.create(virtualTable: "transcripts_fts", using: FTS5()) { table in
                table.column("text")
            }
        }

        migrator.registerMigration("createTranscriptActions") { db in
            try db.create(table: TranscriptActionRecord.databaseTableName) { table in
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

            try db.create(
                index: "idx_transcript_actions_transcriptID",
                on: "transcript_actions",
                columns: ["transcriptID"]
            )
        }

        migrator.registerMigration("addSegmentsColumn") { db in
            try db.alter(table: "transcripts") { table in
                table.add(column: "segments", .text)
            }
        }

        return migrator
    }

    static func ensureParentDirectoryExists(forDatabasePath path: String, fileManager: FileManager) throws {
        let databaseURL = URL(fileURLWithPath: path)
        let parentDirectory = databaseURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: parentDirectory.path) == false {
            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }
    }

    static func defaultDatabaseURL(fileManager: FileManager) -> URL {
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return appSupportDirectory
            .appending(path: "Screamer", directoryHint: .isDirectory)
            .appending(path: "transcripts.sqlite")
    }

    static func makeFTSMatchQuery(from query: String) -> String {
        query
            .split(whereSeparator: \.isWhitespace)
            .map { token -> String in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }
            .joined(separator: " AND ")
    }
}
