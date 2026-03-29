import Foundation
import Testing
@testable import ScreamerCore

struct PasteHelperTests {
    @Test func accessibilityGrantedPastesAndCopies() {
        let pasteboard = MockPasteboard(writeResult: true)
        let permissions = MockAccessibility(granted: true)
        let events = MockPasteEvents(postResult: true)
        let helper = PasteHelper(
            pasteboard: pasteboard,
            accessibility: permissions,
            pasteEvents: events
        )

        let result = helper.copyAndPaste("hello")

        #expect(result == .pastedAndCopied)
        #expect(pasteboard.writes == ["hello"])
        #expect(events.postAttempts == 1)
    }

    @Test func missingAccessibilityFallsBackToClipboardOnly() {
        let pasteboard = MockPasteboard(writeResult: true)
        let permissions = MockAccessibility(granted: false)
        let events = MockPasteEvents(postResult: true)
        let helper = PasteHelper(
            pasteboard: pasteboard,
            accessibility: permissions,
            pasteEvents: events
        )

        let result = helper.copyAndPaste("hello")

        #expect(result == .copiedOnly)
        #expect(pasteboard.writes == ["hello"])
        #expect(events.postAttempts == 0)
    }

    @Test func clipboardWriteFailureReturnsCopyFailed() {
        let pasteboard = MockPasteboard(writeResult: false)
        let permissions = MockAccessibility(granted: true)
        let events = MockPasteEvents(postResult: true)
        let helper = PasteHelper(
            pasteboard: pasteboard,
            accessibility: permissions,
            pasteEvents: events
        )

        let result = helper.copyAndPaste("hello")

        #expect(result == .copyFailed)
        #expect(events.postAttempts == 0)
    }

    @Test func pasteFailureAfterCopyReturnsCopiedOnly() {
        let pasteboard = MockPasteboard(writeResult: true)
        let permissions = MockAccessibility(granted: true)
        let events = MockPasteEvents(postResult: false)
        let helper = PasteHelper(
            pasteboard: pasteboard,
            accessibility: permissions,
            pasteEvents: events
        )

        let result = helper.copyAndPaste("hello")

        #expect(result == .copiedOnly)
        #expect(events.postAttempts == 1)
    }

    @Test func copyOnlyReturnsCopiedOnlyWhenClipboardWriteSucceeds() {
        let pasteboard = MockPasteboard(writeResult: true)
        let permissions = MockAccessibility(granted: false)
        let events = MockPasteEvents(postResult: true)
        let helper = PasteHelper(
            pasteboard: pasteboard,
            accessibility: permissions,
            pasteEvents: events
        )

        let result = helper.copyOnly("hello")

        #expect(result == .copiedOnly)
        #expect(pasteboard.writes == ["hello"])
        #expect(events.postAttempts == 0)
    }

    @Test func copyOnlyReturnsCopyFailedWhenClipboardWriteFails() {
        let pasteboard = MockPasteboard(writeResult: false)
        let permissions = MockAccessibility(granted: true)
        let events = MockPasteEvents(postResult: true)
        let helper = PasteHelper(
            pasteboard: pasteboard,
            accessibility: permissions,
            pasteEvents: events
        )

        let result = helper.copyOnly("hello")

        #expect(result == .copyFailed)
        #expect(events.postAttempts == 0)
    }
}

private final class MockPasteboard: PasteboardWriting, @unchecked Sendable {
    private let writeResult: Bool
    private(set) var writes: [String] = []

    init(writeResult: Bool) {
        self.writeResult = writeResult
    }

    func write(_ value: String) -> Bool {
        writes.append(value)
        return writeResult
    }
}

private struct MockAccessibility: AccessibilityChecking {
    let granted: Bool

    var isAccessibilityGranted: Bool {
        granted
    }
}

private final class MockPasteEvents: PasteEventPosting, @unchecked Sendable {
    private let postResult: Bool
    private(set) var postAttempts = 0

    init(postResult: Bool) {
        self.postResult = postResult
    }

    func postCommandV() -> Bool {
        postAttempts += 1
        return postResult
    }
}
