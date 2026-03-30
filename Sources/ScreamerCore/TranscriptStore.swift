import Foundation
import GRDB

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String
    public let speaker: String?

    public init(start: Double, end: Double, text: String, speaker: String? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
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
    public var speakerMap: [String: String]?
    public var notes: String?

    public init(
        id: Int64? = nil,
        createdAt: Date,
        sourceType: String,
        sourceFileName: String?,
        modelID: String,
        languageHint: String?,
        durationSeconds: Double?,
        text: String,
        segments: [TranscriptSegment]? = nil,
        speakerMap: [String: String]? = nil,
        notes: String? = nil
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
        self.speakerMap = speakerMap
        self.notes = notes
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
        case speakerMap
        case notes
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
        notes = try container.decodeIfPresent(String.self, forKey: .notes)

        if let segmentsJSONString = try container.decodeIfPresent(String.self, forKey: .segments),
           segmentsJSONString.isEmpty == false {
            let data = Data(segmentsJSONString.utf8)
            segments = try JSONDecoder().decode([TranscriptSegment].self, from: data)
        } else {
            segments = nil
        }

        if let speakerMapJSONString = try container.decodeIfPresent(String.self, forKey: .speakerMap),
           speakerMapJSONString.isEmpty == false {
            let data = Data(speakerMapJSONString.utf8)
            speakerMap = try JSONDecoder().decode([String: String].self, from: data)
        } else {
            speakerMap = nil
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
        try container.encodeIfPresent(notes, forKey: .notes)

        if let segments {
            let data = try JSONEncoder().encode(segments)
            let jsonString = String(decoding: data, as: UTF8.self)
            try container.encode(jsonString, forKey: .segments)
        } else {
            try container.encodeNil(forKey: .segments)
        }

        if let speakerMap {
            let data = try JSONEncoder().encode(speakerMap)
            let jsonString = String(decoding: data, as: UTF8.self)
            try container.encode(jsonString, forKey: .speakerMap)
        } else {
            try container.encodeNil(forKey: .speakerMap)
        }
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public func resolvedSpeaker(for segment: TranscriptSegment) -> String? {
        guard let rawSpeaker = normalizedSpeakerLabel(segment.speaker) else { return nil }
        if let mappedSpeaker = normalizedSpeakerLabel(speakerMap?[rawSpeaker]) {
            return mappedSpeaker
        }
        return rawSpeaker
    }

    private func normalizedSpeakerLabel(_ speaker: String?) -> String? {
        guard let speaker else { return nil }
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

public struct TranscriptFilter: Sendable, Equatable {
    public var searchText: String?
    public var dateFrom: Date?
    public var dateTo: Date?
    public var sourceType: String?
    public var modelID: String?
    public var hasSpeakers: Bool?

    public init(
        searchText: String? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        sourceType: String? = nil,
        modelID: String? = nil,
        hasSpeakers: Bool? = nil
    ) {
        self.searchText = searchText
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.sourceType = sourceType
        self.modelID = modelID
        self.hasSpeakers = hasSpeakers
    }
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
        try PerformanceMetrics.shared.measure("db.save") {
            var savedRecord = record
            savedRecord.id = nil

            try dbQueue.write { db in
                try savedRecord.insert(db)

                guard let id = savedRecord.id else {
                    throw TranscriptStoreError.insertedRecordMissingID
                }

                try db.execute(
                    sql: "INSERT INTO transcripts_fts(rowid, text, notes) VALUES (?, ?, ?)",
                    arguments: [id, savedRecord.text, Self.normalizedNotesForFTS(savedRecord.notes)]
                )
            }

            return savedRecord
        }
    }

    public func fetchAll(limit: Int, offset: Int = 0) throws -> [TranscriptRecord] {
        try PerformanceMetrics.shared.measure("db.fetchAll") {
            try dbQueue.read { db in
                try TranscriptRecord.fetchAll(
                    db,
                    sql: """
                    SELECT id, createdAt, sourceType, sourceFileName, modelID, languageHint, durationSeconds, text, segments
                    , speakerMap, notes
                    FROM transcripts
                    ORDER BY createdAt DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                    arguments: [max(limit, 0), max(offset, 0)]
                )
            }
        }
    }

    public func search(query: String, limit: Int) throws -> [TranscriptRecord] {
        try PerformanceMetrics.shared.measure("db.search") {
            try fetchFiltered(TranscriptFilter(searchText: query), limit: limit, offset: 0)
        }
    }

    public func fetchFiltered(_ filter: TranscriptFilter, limit: Int, offset: Int = 0) throws -> [TranscriptRecord] {
        let normalizedSearchText = filter.searchText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldApplySearch = (normalizedSearchText?.isEmpty == false)

        var predicates: [String] = []
        var arguments = StatementArguments()

        if shouldApplySearch, let normalizedSearchText {
            predicates.append("transcripts_fts MATCH ?")
            arguments += [Self.makeFTSMatchQuery(from: normalizedSearchText)]
        }

        if let dateFrom = filter.dateFrom {
            predicates.append("t.createdAt >= ?")
            arguments += [dateFrom]
        }

        if let dateTo = filter.dateTo {
            predicates.append("t.createdAt <= ?")
            arguments += [dateTo]
        }

        if let sourceType = filter.sourceType?.trimmingCharacters(in: .whitespacesAndNewlines),
           sourceType.isEmpty == false {
            predicates.append("t.sourceType = ?")
            arguments += [sourceType]
        }

        if let modelID = filter.modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
           modelID.isEmpty == false {
            predicates.append("t.modelID = ?")
            arguments += [modelID]
        }

        if let hasSpeakers = filter.hasSpeakers {
            if hasSpeakers {
                predicates.append("t.segments LIKE '%\"speaker\"%'")
            } else {
                predicates.append("(t.segments IS NULL OR t.segments NOT LIKE '%\"speaker\"%')")
            }
        }

        let joinClause = shouldApplySearch
            ? "JOIN transcripts_fts ON transcripts_fts.rowid = t.id"
            : ""
        let whereClause = predicates.isEmpty
            ? ""
            : "WHERE \(predicates.joined(separator: " AND "))"

        arguments += [max(limit, 0), max(offset, 0)]

        return try dbQueue.read { db in
            try TranscriptRecord.fetchAll(
                db,
                sql: """
                SELECT t.id, t.createdAt, t.sourceType, t.sourceFileName, t.modelID, t.languageHint, t.durationSeconds, t.text, t.segments, t.speakerMap, t.notes
                FROM transcripts AS t
                \(joinClause)
                \(whereClause)
                ORDER BY t.createdAt DESC, t.id DESC
                LIMIT ? OFFSET ?
                """,
                arguments: arguments
            )
        }
    }

    public func fetchDistinctModelIDs() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT DISTINCT modelID
                FROM transcripts
                WHERE modelID IS NOT NULL AND modelID <> ''
                ORDER BY modelID ASC
                """
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

    public func updateSpeakerMap(id: Int64, speakerMap: [String: String]?) throws {
        let normalizedMap = Self.normalizeSpeakerMap(speakerMap)
        let speakerMapJSONString: String? = try normalizedMap.map { map in
            let data = try JSONEncoder().encode(map)
            return String(decoding: data, as: UTF8.self)
        }

        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transcripts SET speakerMap = ? WHERE id = ?",
                arguments: [speakerMapJSONString, id]
            )
        }
    }

    public func updateNotes(id: Int64, notes: String?) throws {
        let normalizedNotes = Self.normalizeNotes(notes)
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transcripts SET notes = ? WHERE id = ?",
                arguments: [normalizedNotes, id]
            )
            try db.execute(
                sql: "UPDATE transcripts_fts SET notes = ? WHERE rowid = ?",
                arguments: [Self.normalizedNotesForFTS(normalizedNotes), id]
            )
        }
    }

    public func delete(ids: [Int64]) throws {
        guard ids.isEmpty == false else { return }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let arguments = StatementArguments(ids)
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM transcripts WHERE id IN (\(placeholders))",
                arguments: arguments
            )
            try db.execute(
                sql: "DELETE FROM transcripts_fts WHERE rowid IN (\(placeholders))",
                arguments: arguments
            )
        }
    }

    public func countActions(forTranscriptIDs transcriptIDs: [Int64]) throws -> Int {
        guard transcriptIDs.isEmpty == false else { return 0 }
        let placeholders = Array(repeating: "?", count: transcriptIDs.count).joined(separator: ",")
        return try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM transcript_actions WHERE transcriptID IN (\(placeholders))",
                arguments: StatementArguments(transcriptIDs)
            ) ?? 0
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
                table.column("speakerMap", .text)
                table.column("notes", .text)
            }

            try db.create(index: "idx_transcripts_createdAt", on: "transcripts", columns: ["createdAt"])

            try db.create(virtualTable: "transcripts_fts", using: FTS5()) { table in
                table.column("text")
                table.column("notes")
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
            if try columnExists("segments", in: "transcripts", db: db) == false {
                try db.alter(table: "transcripts") { table in
                    table.add(column: "segments", .text)
                }
            }
        }

        migrator.registerMigration("addSpeakerMapColumn") { db in
            if try columnExists("speakerMap", in: "transcripts", db: db) == false {
                try db.alter(table: "transcripts") { table in
                    table.add(column: "speakerMap", .text)
                }
            }
        }

        migrator.registerMigration("addNotesColumn") { db in
            if try columnExists("notes", in: "transcripts", db: db) == false {
                try db.alter(table: "transcripts") { table in
                    table.add(column: "notes", .text)
                }
            }
        }

        migrator.registerMigration("rebuildTranscriptsFTSWithNotes") { db in
            try db.drop(table: "transcripts_fts")
            try db.create(virtualTable: "transcripts_fts", using: FTS5()) { table in
                table.column("text")
                table.column("notes")
            }
            try db.execute(
                sql: """
                INSERT INTO transcripts_fts(rowid, text, notes)
                SELECT id, text, COALESCE(notes, '')
                FROM transcripts
                """
            )
            try db.execute(sql: "INSERT INTO transcripts_fts(transcripts_fts) VALUES('rebuild')")
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

    static func columnExists(_ columnName: String, in tableName: String, db: Database) throws -> Bool {
        try Row.fetchAll(db, sql: "PRAGMA table_info(\(tableName))")
            .contains { row in
                (row["name"] as String?) == columnName
            }
    }

    static func normalizeSpeakerMap(_ speakerMap: [String: String]?) -> [String: String]? {
        guard let speakerMap else { return nil }
        let normalized = speakerMap.reduce(into: [String: String]()) { partialResult, entry in
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false, value.isEmpty == false else { return }
            partialResult[key] = value
        }
        return normalized.isEmpty ? nil : normalized
    }

    static func normalizeNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : notes
    }

    static func normalizedNotesForFTS(_ notes: String?) -> String {
        notes ?? ""
    }
}
