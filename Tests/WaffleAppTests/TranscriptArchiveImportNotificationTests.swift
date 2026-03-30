import Foundation
import Testing
@testable import WaffleApp

@Suite
struct TranscriptArchiveImportNotificationTests {
    @Test func encodedArchiveURLsCanBeDecodedFromNotification() {
        let urls = [
            URL(fileURLWithPath: "/tmp/one.waffle"),
            URL(fileURLWithPath: "/tmp/two.waffle"),
        ]
        let notification = Notification(
            name: .waffleImportTranscriptArchive,
            object: nil,
            userInfo: TranscriptArchiveImportNotification.userInfo(for: urls)
        )

        let decoded = TranscriptArchiveImportNotification.urls(from: notification)

        #expect(decoded == urls)
    }

    @Test func decodingReturnsNilWithoutArchiveURLPayload() {
        let notification = Notification(name: .waffleImportTranscriptArchive)

        #expect(TranscriptArchiveImportNotification.urls(from: notification) == nil)
    }
}
