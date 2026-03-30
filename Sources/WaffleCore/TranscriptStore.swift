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
    public var reviewStatus: String?
    public var notes: String?
    public var audioFilePath: String?

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
        reviewStatus: String? = nil,
        notes: String? = nil,
        audioFilePath: String? = nil
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
        self.reviewStatus = reviewStatus
        self.notes = notes
        self.audioFilePath = audioFilePath
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
        case reviewStatus
        case notes
        case audioFilePath
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
        audioFilePath = try container.decodeIfPresent(String.self, forKey: .audioFilePath)

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

        reviewStatus = try container.decodeIfPresent(String.self, forKey: .reviewStatus)
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
        try container.encodeIfPresent(audioFilePath, forKey: .audioFilePath)

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

        try container.encodeIfPresent(reviewStatus, forKey: .reviewStatus)
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

public enum ReviewStatus {
    public static let approved = "approved"
    public static let dismissed = "dismissed"
}

public struct TranscriptArchiveImportResult: Equatable, Sendable {
    public var importedTranscriptCount: Int
    public var importedActionCount: Int
    public var skippedDuplicateCount: Int
    public var firstImportedTranscriptID: Int64?

    public init(
        importedTranscriptCount: Int,
        importedActionCount: Int,
        skippedDuplicateCount: Int,
        firstImportedTranscriptID: Int64?
    ) {
        self.importedTranscriptCount = importedTranscriptCount
        self.importedActionCount = importedActionCount
        self.skippedDuplicateCount = skippedDuplicateCount
        self.firstImportedTranscriptID = firstImportedTranscriptID
    }
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

public struct TranscriptStatistics: Equatable, Sendable {
    public let transcriptCount: Int
    public let totalWords: Int
    public let totalDurationSeconds: Double
    public let averageDurationSeconds: Double
    public let byModel: [String: Int]
    public let dailyCounts: [String: Int]

    public init(
        transcriptCount: Int,
        totalWords: Int,
        totalDurationSeconds: Double,
        averageDurationSeconds: Double,
        byModel: [String: Int],
        dailyCounts: [String: Int]
    ) {
        self.transcriptCount = transcriptCount
        self.totalWords = totalWords
        self.totalDurationSeconds = totalDurationSeconds
        self.averageDurationSeconds = averageDurationSeconds
        self.byModel = byModel
        self.dailyCounts = dailyCounts
    }
}

public final class TranscriptStore: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public var databaseQueue: DatabaseQueue {
        dbQueue
    }

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
                    , speakerMap, reviewStatus, notes, audioFilePath
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
                SELECT t.id, t.createdAt, t.sourceType, t.sourceFileName, t.modelID, t.languageHint, t.durationSeconds, t.text, t.segments, t.speakerMap, t.reviewStatus, t.notes, t.audioFilePath
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

    public func fetchUnreviewed(limit: Int = 50) throws -> [TranscriptRecord] {
        try dbQueue.read { db in
            try TranscriptRecord.fetchAll(
                db,
                sql: """
                SELECT id, createdAt, sourceType, sourceFileName, modelID, languageHint, durationSeconds, text, segments
                , speakerMap, reviewStatus, notes, audioFilePath
                FROM transcripts
                WHERE reviewStatus IS NULL
                ORDER BY createdAt DESC, id DESC
                LIMIT ?
                """,
                arguments: [max(limit, 0)]
            )
        }
    }

    public func setReviewStatus(id: Int64, status: String?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transcripts SET reviewStatus = ? WHERE id = ?",
                arguments: [status, id]
            )
        }
    }

    public func unreviewedCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM transcripts WHERE reviewStatus IS NULL"
            ) ?? 0
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

    public func statistics(since: Date? = nil) throws -> TranscriptStatistics {
        try dbQueue.read { db in
            let filteredSQLSuffix = since == nil ? "" : " WHERE createdAt >= ?"
            let filteredArguments = since.map { StatementArguments([$0]) } ?? StatementArguments()

            let transcriptCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM transcripts\(filteredSQLSuffix)",
                arguments: filteredArguments
            ) ?? 0

            let allText = try String.fetchAll(
                db,
                sql: "SELECT text FROM transcripts\(filteredSQLSuffix)",
                arguments: filteredArguments
            )
            let totalWords = allText.reduce(0) { partialResult, text in
                partialResult + text.split(whereSeparator: \.isWhitespace).count
            }

            let totalDurationSeconds = try Double.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(durationSeconds), 0) FROM transcripts\(filteredSQLSuffix)",
                arguments: filteredArguments
            ) ?? 0

            let groupedByModelRows = try Row.fetchAll(
                db,
                sql: """
                SELECT modelID, COUNT(*) AS count
                FROM transcripts\(filteredSQLSuffix)
                GROUP BY modelID
                """
                ,
                arguments: filteredArguments
            )
            var byModel: [String: Int] = [:]
            for row in groupedByModelRows {
                guard let modelID = row["modelID"] as String? else { continue }
                let count = Int((row["count"] as Int64?) ?? 0)
                byModel[modelID] = count
            }

            let thirtyDaysAgo = Date().addingTimeInterval(-(30 * 24 * 60 * 60))
            let dailyRows = try Row.fetchAll(
                db,
                sql: """
                SELECT COALESCE(
                           strftime('%Y-%m-%d', datetime(createdAt, 'unixepoch')),
                           strftime('%Y-%m-%d', createdAt)
                       ) AS day,
                       COUNT(*) AS count
                FROM transcripts
                WHERE createdAt >= ?
                GROUP BY day
                """,
                arguments: [thirtyDaysAgo]
            )
            var dailyCounts: [String: Int] = [:]
            for row in dailyRows {
                guard let day = row["day"] as String? else { continue }
                let count = Int((row["count"] as Int64?) ?? 0)
                dailyCounts[day] = count
            }

            let averageDurationSeconds = transcriptCount > 0
                ? totalDurationSeconds / Double(transcriptCount)
                : 0

            return TranscriptStatistics(
                transcriptCount: transcriptCount,
                totalWords: totalWords,
                totalDurationSeconds: totalDurationSeconds,
                averageDurationSeconds: averageDurationSeconds,
                byModel: byModel,
                dailyCounts: dailyCounts
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

    /// Replaces the segments JSON and updates the full text by joining segment texts.
    public func updateSegments(id: Int64, segments: [TranscriptSegment]) throws {
        let updatedText = segments.map(\.text).joined(separator: " ")
        let segmentsData = try JSONEncoder().encode(segments)
        let segmentsJSONString = String(decoding: segmentsData, as: UTF8.self)

        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transcripts SET text = ?, segments = ? WHERE id = ?",
                arguments: [updatedText, segmentsJSONString, id]
            )

            guard db.changesCount > 0 else {
                throw RecordError.recordNotFound(
                    databaseTableName: TranscriptRecord.databaseTableName,
                    key: ["id": id.databaseValue]
                )
            }

            try db.execute(
                sql: "UPDATE transcripts_fts SET text = ? WHERE rowid = ?",
                arguments: [updatedText, id]
            )
        }
    }

    /// Replaces the full text only (for when no segments exist).
    public func updateText(id: Int64, text: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transcripts SET text = ? WHERE id = ?",
                arguments: [text, id]
            )

            guard db.changesCount > 0 else {
                throw RecordError.recordNotFound(
                    databaseTableName: TranscriptRecord.databaseTableName,
                    key: ["id": id.databaseValue]
                )
            }

            try db.execute(
                sql: "UPDATE transcripts_fts SET text = ? WHERE rowid = ?",
                arguments: [text, id]
            )
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

    public func updateAudioFilePath(id: Int64, path: String?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE transcripts SET audioFilePath = ? WHERE id = ?",
                arguments: [path, id]
            )
        }
    }

    public func saveEmbeddings(_ embeddings: [String: [Float]], transcriptID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM transcript_speaker_embeddings WHERE transcriptID = ?",
                arguments: [transcriptID]
            )

            for (speakerLabel, embedding) in embeddings {
                let normalizedLabel = speakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalizedLabel.isEmpty == false else { continue }
                guard embedding.isEmpty == false else { continue }

                try db.execute(
                    sql: """
                    INSERT INTO transcript_speaker_embeddings(transcriptID, speakerLabel, embedding)
                    VALUES (?, ?, ?)
                    """,
                    arguments: [transcriptID, normalizedLabel, Self.encodeFloatArray(embedding)]
                )
            }
        }
    }

    public func fetchEmbeddings(transcriptID: Int64) throws -> [String: [Float]] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT speakerLabel, embedding
                FROM transcript_speaker_embeddings
                WHERE transcriptID = ?
                """,
                arguments: [transcriptID]
            )

            var embeddings: [String: [Float]] = [:]
            for row in rows {
                guard let speakerLabel = row["speakerLabel"] as String? else { continue }
                guard let embeddingData = row["embedding"] as Data? else { continue }
                let decoded = Self.decodeFloatArray(embeddingData)
                guard decoded.isEmpty == false else { continue }
                embeddings[speakerLabel] = decoded
            }
            return embeddings
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

    public func importArchive(_ archive: WaffleArchive) throws -> TranscriptArchiveImportResult {
        var importedTranscriptCount = 0
        var importedActionCount = 0
        var skippedDuplicateCount = 0
        var firstImportedTranscriptID: Int64?

        try dbQueue.write { db in
            for archivedTranscript in archive.transcripts {
                guard archivedTranscript.record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                else {
                    throw ArchiveError.invalidData("Transcript text cannot be empty.")
                }

                if try Self.archiveRecordIsDuplicate(archivedTranscript.record, db: db) {
                    skippedDuplicateCount += 1
                    continue
                }

                var record = archivedTranscript.record
                record.id = nil
                try record.insert(db)

                guard let insertedID = record.id else {
                    throw TranscriptStoreError.insertedRecordMissingID
                }

                try db.execute(
                    sql: "INSERT INTO transcripts_fts(rowid, text, notes) VALUES (?, ?, ?)",
                    arguments: [insertedID, record.text, Self.normalizedNotesForFTS(record.notes)]
                )

                if firstImportedTranscriptID == nil {
                    firstImportedTranscriptID = insertedID
                }
                importedTranscriptCount += 1

                for archivedAction in archivedTranscript.actions {
                    var action = archivedAction
                    action.id = nil
                    action.transcriptID = insertedID
                    try action.insert(db)
                    importedActionCount += 1
                }
            }
        }

        return TranscriptArchiveImportResult(
            importedTranscriptCount: importedTranscriptCount,
            importedActionCount: importedActionCount,
            skippedDuplicateCount: skippedDuplicateCount,
            firstImportedTranscriptID: firstImportedTranscriptID
        )
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
                table.column("reviewStatus", .text)
                table.column("notes", .text)
                table.column("audioFilePath", .text)
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

        migrator.registerMigration("addAudioFilePathColumn") { db in
            if try columnExists("audioFilePath", in: "transcripts", db: db) == false {
                try db.alter(table: "transcripts") { table in
                    table.add(column: "audioFilePath", .text)
                }
            }
        }

        migrator.registerMigration("addReviewStatusColumn") { db in
            if try columnExists("reviewStatus", in: "transcripts", db: db) == false {
                try db.alter(table: "transcripts") { table in
                    table.add(column: "reviewStatus", .text)
                }
            }
        }

        migrator.registerMigration("createSpeakerProfiles") { db in
            if try tableExists("speaker_profiles", db: db) == false {
                try db.create(table: "speaker_profiles") { table in
                    table.column("id", .text).notNull().primaryKey()
                    table.column("displayName", .text).notNull()
                    table.column("createdAt", .double).notNull()
                    table.column("lastSeenAt", .double).notNull()
                    table.column("averageEmbedding", .blob).notNull()
                    table.column("transcriptCount", .integer).notNull().defaults(to: 1)
                }
            }
        }

        migrator.registerMigration("createTranscriptSpeakerEmbeddings") { db in
            if try tableExists("transcript_speaker_embeddings", db: db) == false {
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
            .appending(path: "Waffle", directoryHint: .isDirectory)
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

    static func tableExists(_ tableName: String, db: Database) throws -> Bool {
        try String.fetchOne(
            db,
            sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
            arguments: [tableName]
        ) != nil
    }

    static func encodeFloatArray(_ embedding: [Float]) -> Data {
        var array = embedding
        return Data(bytes: &array, count: array.count * MemoryLayout<Float>.size)
    }

    static func decodeFloatArray(_ data: Data) -> [Float] {
        guard data.count.isMultiple(of: MemoryLayout<Float>.size) else { return [] }
        return data.withUnsafeBytes { rawBytes in
            Array(rawBytes.bindMemory(to: Float.self))
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

    static func archiveRecordIsDuplicate(_ record: TranscriptRecord, db: Database) throws -> Bool {
        let textPrefix = String(record.text.prefix(200))
        let existingCreatedAts = try Date.fetchAll(
            db,
            sql: """
            SELECT createdAt
            FROM transcripts
            WHERE modelID = ? AND substr(text, 1, 200) = ?
            """,
            arguments: [record.modelID, textPrefix]
        )
        let archiveSecond = Self.unixSecond(for: record.createdAt)
        return existingCreatedAts.contains { existingDate in
            Self.unixSecond(for: existingDate) == archiveSecond
        }
    }

    static func unixSecond(for date: Date) -> Int64 {
        Int64(floor(date.timeIntervalSince1970))
    }
}
