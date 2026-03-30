import Testing
@testable import WaffleApp

@Suite
struct AccessibilityInteractionTests {
    @Test func reviewQueueProgressLabelReflectsQueueState() {
        #expect(ReviewQueueViewModel.progressTitle(currentIndex: 0, totalCount: 0) == "All caught up!")
        #expect(
            ReviewQueueViewModel.progressAccessibilityLabel(currentIndex: 0, totalCount: 0)
                == "Review queue is empty"
        )

        #expect(ReviewQueueViewModel.progressTitle(currentIndex: 1, totalCount: 2) == "2 of 2")
        #expect(
            ReviewQueueViewModel.progressAccessibilityLabel(currentIndex: 1, totalCount: 2)
                == "Transcript 2 of 2 in review queue"
        )
    }

    @Test func transcriptHistoryRowAccessibilityChildrenSwitchWhenExpanded() {
        #expect(TranscriptHistoryView.usesCombinedAccessibilityChildren(isExpanded: false))
        #expect(TranscriptHistoryView.usesCombinedAccessibilityChildren(isExpanded: true) == false)
    }
}
