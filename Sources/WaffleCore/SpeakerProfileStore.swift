import Foundation
import GRDB

public struct SpeakerProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var createdAt: Date
    public var lastSeenAt: Date
    public var averageEmbedding: [Float]
    public var transcriptCount: Int

    public init(
        id: UUID = UUID(),
        displayName: String,
        createdAt: Date = Date(),
        lastSeenAt: Date = Date(),
        averageEmbedding: [Float],
        transcriptCount: Int = 1
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.averageEmbedding = averageEmbedding
        self.transcriptCount = transcriptCount
    }
}

public enum SpeakerProfileStoreError: Error {
    case profileNotFound(UUID)
}

public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, a.isEmpty == false else { return 0 }
    let dot = zip(a, b).reduce(0.0 as Float) { partialResult, pair in
        partialResult + pair.0 * pair.1
    }
    let normA = sqrt(a.reduce(0.0 as Float) { $0 + $1 * $1 })
    let normB = sqrt(b.reduce(0.0 as Float) { $0 + $1 * $1 })
    guard normA > 0, normB > 0 else { return 0 }
    return dot / (normA * normB)
}

public final class SpeakerProfileStore: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(databaseQueue: DatabaseQueue) {
        self.dbQueue = databaseQueue
    }

    public func fetchAll() throws -> [SpeakerProfile] {
        try dbQueue.read { db in
            try Self.fetchAll(db: db)
        }
    }

    public func fetch(id: UUID) throws -> SpeakerProfile? {
        try dbQueue.read { db in
            try Self.fetchProfile(id: id, db: db)
        }
    }

    public func save(_ profile: SpeakerProfile) throws {
        try dbQueue.write { db in
            try Self.save(profile: profile, db: db)
        }
    }

    public func delete(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM speaker_profiles WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    public func rename(id: UUID, displayName: String) throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else { return }
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE speaker_profiles SET displayName = ? WHERE id = ?",
                arguments: [trimmedName, id.uuidString]
            )
        }
    }

    public func findMatch(for embedding: [Float], threshold: Float) throws -> SpeakerProfile? {
        guard embedding.isEmpty == false else { return nil }
        let clampedThreshold = min(max(threshold, 0), 1)
        let profiles = try fetchAll()

        var bestMatch: SpeakerProfile?
        var bestScore: Float = clampedThreshold

        for profile in profiles {
            let score = cosineSimilarity(profile.averageEmbedding, embedding)
            if score >= clampedThreshold, score > bestScore {
                bestScore = score
                bestMatch = profile
            }
        }

        return bestMatch
    }

    public func updateAverageEmbedding(id: UUID, newEmbedding: [Float]) throws {
        guard newEmbedding.isEmpty == false else { return }

        try dbQueue.write { db in
            guard var profile = try Self.fetchProfile(id: id, db: db) else {
                throw SpeakerProfileStoreError.profileNotFound(id)
            }

            let existingCount = max(profile.transcriptCount, 1)
            let updatedAverage: [Float]
            if profile.averageEmbedding.count == newEmbedding.count {
                updatedAverage = zip(profile.averageEmbedding, newEmbedding).map { existing, incoming in
                    (existing * Float(existingCount) + incoming) / Float(existingCount + 1)
                }
            } else {
                updatedAverage = newEmbedding
            }

            profile.averageEmbedding = updatedAverage
            profile.transcriptCount = existingCount + 1
            profile.lastSeenAt = Date()

            try Self.save(profile: profile, db: db)
        }
    }

    @discardableResult
    public func matchOrCreateProfile(
        for embedding: [Float],
        threshold: Float
    ) throws -> SpeakerProfile {
        if let match = try findMatch(for: embedding, threshold: threshold) {
            try updateAverageEmbedding(id: match.id, newEmbedding: embedding)
            return try fetch(id: match.id) ?? match
        }

        let now = Date()
        let created = SpeakerProfile(
            displayName: try nextAutoSpeakerName(),
            createdAt: now,
            lastSeenAt: now,
            averageEmbedding: embedding,
            transcriptCount: 1
        )
        try save(created)
        return created
    }

    public func nextAutoSpeakerName() throws -> String {
        let profiles = try fetchAll()
        let prefix = "speaker "
        var highestValue = 0

        for profile in profiles {
            let lowered = profile.displayName.lowercased()
            guard lowered.hasPrefix(prefix) else { continue }
            let numericPart = lowered.dropFirst(prefix.count)
            guard let value = Int(numericPart), value > highestValue else { continue }
            highestValue = value
        }

        return "Speaker \(highestValue + 1)"
    }

    public func mergeProfiles(
        primaryID: UUID,
        secondaryID: UUID,
        keepDisplayName: String
    ) throws {
        guard primaryID != secondaryID else { return }

        try dbQueue.write { db in
            guard let primary = try Self.fetchProfile(id: primaryID, db: db) else {
                throw SpeakerProfileStoreError.profileNotFound(primaryID)
            }
            guard let secondary = try Self.fetchProfile(id: secondaryID, db: db) else {
                throw SpeakerProfileStoreError.profileNotFound(secondaryID)
            }

            let mergedEmbedding: [Float]
            if primary.averageEmbedding.count == secondary.averageEmbedding.count {
                let totalCount = max(primary.transcriptCount, 0) + max(secondary.transcriptCount, 0)
                if totalCount > 0 {
                    mergedEmbedding = zip(primary.averageEmbedding, secondary.averageEmbedding).map { lhs, rhs in
                        let lhsWeight = Float(max(primary.transcriptCount, 0))
                        let rhsWeight = Float(max(secondary.transcriptCount, 0))
                        return ((lhs * lhsWeight) + (rhs * rhsWeight)) / Float(totalCount)
                    }
                } else {
                    mergedEmbedding = primary.averageEmbedding
                }
            } else if primary.averageEmbedding.isEmpty {
                mergedEmbedding = secondary.averageEmbedding
            } else {
                mergedEmbedding = primary.averageEmbedding
            }

            let mergedProfile = SpeakerProfile(
                id: primary.id,
                displayName: keepDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? primary.displayName
                    : keepDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: min(primary.createdAt, secondary.createdAt),
                lastSeenAt: max(primary.lastSeenAt, secondary.lastSeenAt),
                averageEmbedding: mergedEmbedding,
                transcriptCount: primary.transcriptCount + secondary.transcriptCount
            )

            try Self.save(profile: mergedProfile, db: db)
            try db.execute(
                sql: "DELETE FROM speaker_profiles WHERE id = ?",
                arguments: [secondaryID.uuidString]
            )
        }
    }
}

private extension SpeakerProfileStore {
    static func fetchAll(db: Database) throws -> [SpeakerProfile] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, displayName, createdAt, lastSeenAt, averageEmbedding, transcriptCount
            FROM speaker_profiles
            ORDER BY displayName COLLATE NOCASE ASC, createdAt ASC
            """
        )
        return rows.compactMap(Self.profileFromRow)
    }

    static func fetchProfile(id: UUID, db: Database) throws -> SpeakerProfile? {
        let row = try Row.fetchOne(
            db,
            sql: """
            SELECT id, displayName, createdAt, lastSeenAt, averageEmbedding, transcriptCount
            FROM speaker_profiles
            WHERE id = ?
            LIMIT 1
            """,
            arguments: [id.uuidString]
        )
        guard let row else { return nil }
        return profileFromRow(row)
    }

    static func save(profile: SpeakerProfile, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO speaker_profiles(id, displayName, createdAt, lastSeenAt, averageEmbedding, transcriptCount)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                displayName = excluded.displayName,
                createdAt = excluded.createdAt,
                lastSeenAt = excluded.lastSeenAt,
                averageEmbedding = excluded.averageEmbedding,
                transcriptCount = excluded.transcriptCount
            """,
            arguments: [
                profile.id.uuidString,
                profile.displayName,
                profile.createdAt.timeIntervalSince1970,
                profile.lastSeenAt.timeIntervalSince1970,
                encodeEmbedding(profile.averageEmbedding),
                profile.transcriptCount,
            ]
        )
    }

    static func profileFromRow(_ row: Row) -> SpeakerProfile? {
        guard
            let idString = row["id"] as String?,
            let id = UUID(uuidString: idString),
            let displayName = row["displayName"] as String?,
            let createdAtSeconds = row["createdAt"] as Double?,
            let lastSeenAtSeconds = row["lastSeenAt"] as Double?,
            let averageEmbeddingData = row["averageEmbedding"] as Data?,
            let transcriptCount = row["transcriptCount"] as Int?
        else {
            return nil
        }

        return SpeakerProfile(
            id: id,
            displayName: displayName,
            createdAt: Date(timeIntervalSince1970: createdAtSeconds),
            lastSeenAt: Date(timeIntervalSince1970: lastSeenAtSeconds),
            averageEmbedding: decodeEmbedding(averageEmbeddingData),
            transcriptCount: transcriptCount
        )
    }

    static func encodeEmbedding(_ embedding: [Float]) -> Data {
        var array = embedding
        return Data(bytes: &array, count: array.count * MemoryLayout<Float>.size)
    }

    static func decodeEmbedding(_ data: Data) -> [Float] {
        guard data.count.isMultiple(of: MemoryLayout<Float>.size) else { return [] }
        return data.withUnsafeBytes { rawBytes in
            Array(rawBytes.bindMemory(to: Float.self))
        }
    }
}
