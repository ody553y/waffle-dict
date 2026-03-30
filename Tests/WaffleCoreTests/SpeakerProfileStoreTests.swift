import Foundation
import Testing
@testable import WaffleCore

@Suite(.serialized)
struct SpeakerProfileStoreTests {
    @Test func cosineSimilarityReturnsExpectedValues() {
        #expect(cosineSimilarity([1, 0], [0, 1]) == 0)
        #expect(abs(cosineSimilarity([1, 1], [1, 1]) - 1) < 0.0001)
        #expect(cosineSimilarity([], []) == 0)
        #expect(cosineSimilarity([1, 2], [1]) == 0)
    }

    @Test func findMatchReturnsProfileAboveThreshold() throws {
        let transcriptStore = try TranscriptStore(databasePath: ":memory:")
        let profileStore = SpeakerProfileStore(databaseQueue: transcriptStore.databaseQueue)

        let profile = SpeakerProfile(
            displayName: "Alice",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastSeenAt: Date(timeIntervalSince1970: 1_700_000_000),
            averageEmbedding: [1, 0, 0],
            transcriptCount: 1
        )
        try profileStore.save(profile)

        let matched = try profileStore.findMatch(
            for: [0.99, 0.01, 0],
            threshold: 0.85
        )
        #expect(matched?.displayName == "Alice")

        let noMatch = try profileStore.findMatch(
            for: [0, 1, 0],
            threshold: 0.85
        )
        #expect(noMatch == nil)
    }

    @Test func updateAverageEmbeddingUsesRunningAverageFormula() throws {
        let transcriptStore = try TranscriptStore(databasePath: ":memory:")
        let profileStore = SpeakerProfileStore(databaseQueue: transcriptStore.databaseQueue)
        let id = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
        let profile = SpeakerProfile(
            id: id,
            displayName: "Speaker 1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastSeenAt: Date(timeIntervalSince1970: 1_700_000_000),
            averageEmbedding: [1, 3],
            transcriptCount: 2
        )
        try profileStore.save(profile)

        try profileStore.updateAverageEmbedding(id: id, newEmbedding: [3, 5])

        let updated = try #require(try profileStore.fetch(id: id))
        #expect(updated.transcriptCount == 3)
        #expect(abs(updated.averageEmbedding[0] - 1.6666666) < 0.0001)
        #expect(abs(updated.averageEmbedding[1] - 3.6666667) < 0.0001)
        #expect(updated.lastSeenAt > profile.lastSeenAt)
    }

    @Test func mergeProfilesCombinesCountsAndWeightedEmbedding() throws {
        let transcriptStore = try TranscriptStore(databasePath: ":memory:")
        let profileStore = SpeakerProfileStore(databaseQueue: transcriptStore.databaseQueue)

        let aliceID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let bobID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

        try profileStore.save(
            SpeakerProfile(
                id: aliceID,
                displayName: "Alice",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastSeenAt: Date(timeIntervalSince1970: 1_700_000_010),
                averageEmbedding: [1, 1],
                transcriptCount: 2
            )
        )
        try profileStore.save(
            SpeakerProfile(
                id: bobID,
                displayName: "Bob",
                createdAt: Date(timeIntervalSince1970: 1_700_000_020),
                lastSeenAt: Date(timeIntervalSince1970: 1_700_000_030),
                averageEmbedding: [3, 5],
                transcriptCount: 1
            )
        )

        try profileStore.mergeProfiles(
            primaryID: aliceID,
            secondaryID: bobID,
            keepDisplayName: "Alice"
        )

        let merged = try #require(try profileStore.fetch(id: aliceID))
        #expect(merged.displayName == "Alice")
        #expect(merged.transcriptCount == 3)
        #expect(abs(merged.averageEmbedding[0] - 1.6666666) < 0.0001)
        #expect(abs(merged.averageEmbedding[1] - 2.3333333) < 0.0001)
        #expect(try profileStore.fetch(id: bobID) == nil)
    }
}
