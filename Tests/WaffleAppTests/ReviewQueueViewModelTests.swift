import Foundation
import Testing
@testable import WaffleApp
@testable import WaffleCore

@MainActor
@Suite(.serialized)
struct ReviewQueueViewModelTests {
    @Test func approveSetsStatusAndAdvancesToNextTranscript() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let older = try seedTranscript(text: "older", timestamp: 1_710_000_000, store: store)
        let newer = try seedTranscript(text: "newer", timestamp: 1_710_000_010, store: store)
        let vm = ReviewQueueViewModel()

        try vm.load(store: store)
        #expect(vm.current?.id == newer.id)

        try vm.approve(store: store)

        let newerID = try #require(newer.id)
        let approved = try #require(try store.fetchOne(id: newerID))
        #expect(approved.reviewStatus == ReviewStatus.approved)
        #expect(vm.current?.id == older.id)
        #expect(vm.transcripts.count == 1)
    }

    @Test func dismissSetsStatusAndRemovesCurrentTranscript() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let transcript = try seedTranscript(text: "dismiss-me", timestamp: 1_710_000_000, store: store)
        let vm = ReviewQueueViewModel()

        try vm.load(store: store)
        try vm.dismiss(store: store)

        let transcriptID = try #require(transcript.id)
        let dismissed = try #require(try store.fetchOne(id: transcriptID))
        #expect(dismissed.reviewStatus == ReviewStatus.dismissed)
        #expect(vm.current == nil)
        #expect(vm.transcripts.isEmpty)
    }

    @Test func skipAndBackNavigateWithinBounds() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        _ = try seedTranscript(text: "one", timestamp: 1_710_000_000, store: store)
        _ = try seedTranscript(text: "two", timestamp: 1_710_000_010, store: store)
        _ = try seedTranscript(text: "three", timestamp: 1_710_000_020, store: store)
        let vm = ReviewQueueViewModel()

        try vm.load(store: store)
        #expect(vm.currentIndex == 0)

        vm.skip()
        #expect(vm.currentIndex == 1)
        vm.skip()
        #expect(vm.currentIndex == 2)
        vm.skip()
        #expect(vm.currentIndex == 2)

        vm.back()
        #expect(vm.currentIndex == 1)
        vm.back()
        #expect(vm.currentIndex == 0)
        vm.back()
        #expect(vm.currentIndex == 0)
    }

    @Test func remainingCountDecreasesAfterApproveAndDismiss() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        _ = try seedTranscript(text: "a", timestamp: 1_710_000_000, store: store)
        _ = try seedTranscript(text: "b", timestamp: 1_710_000_010, store: store)
        let vm = ReviewQueueViewModel()

        try vm.load(store: store)
        #expect(vm.remaining == 2)

        try vm.approve(store: store)
        #expect(vm.remaining == 1)

        try vm.dismiss(store: store)
        #expect(vm.remaining == 0)
    }

    @Test func loadShowsEmptyStateWhenEverythingIsReviewed() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let transcript = try seedTranscript(text: "already reviewed", timestamp: 1_710_000_000, store: store)
        try store.setReviewStatus(id: try #require(transcript.id), status: ReviewStatus.approved)
        let vm = ReviewQueueViewModel()

        try vm.load(store: store)

        #expect(vm.current == nil)
        #expect(vm.transcripts.isEmpty)
        #expect(vm.remaining == 0)
    }

    @Test func openQueueNotificationSetsPresentedState() {
        let state = ReviewQueueMenuState(store: nil)

        #expect(state.isQueuePresented == false)
        state.handleOpenQueueNotification(Notification(name: .waffleOpenReviewQueue))
        #expect(state.isQueuePresented)
    }

    @Test func refreshBadgeCountTracksUnreviewedTranscripts() throws {
        let store = try TranscriptStore(databasePath: ":memory:")
        let first = try seedTranscript(text: "first", timestamp: 1_710_000_000, store: store)
        let second = try seedTranscript(text: "second", timestamp: 1_710_000_010, store: store)
        let third = try seedTranscript(text: "third", timestamp: 1_710_000_020, store: store)
        try store.setReviewStatus(id: try #require(third.id), status: ReviewStatus.dismissed)

        let state = ReviewQueueMenuState(store: store)
        state.refreshBadgeCount()
        #expect(state.unreviewedCount == 2)

        try store.setReviewStatus(id: try #require(second.id), status: ReviewStatus.approved)
        state.refreshBadgeCount()
        #expect(state.unreviewedCount == 1)

        try store.setReviewStatus(id: try #require(first.id), status: ReviewStatus.approved)
        state.refreshBadgeCount()
        #expect(state.unreviewedCount == 0)
    }

    private func seedTranscript(
        text: String,
        timestamp: TimeInterval,
        store: TranscriptStore
    ) throws -> TranscriptRecord {
        try store.save(
            TranscriptRecord(
                createdAt: Date(timeIntervalSince1970: timestamp),
                sourceType: "dictation",
                sourceFileName: nil,
                modelID: "whisper-small",
                languageHint: nil,
                durationSeconds: nil,
                text: text
            )
        )
    }
}
