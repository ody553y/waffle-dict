import Foundation

enum TranscriptArchiveImportNotification {
    private static let archiveURLsUserInfoKey = "archiveURLs"

    static func userInfo(for urls: [URL]) -> [AnyHashable: Any] {
        [archiveURLsUserInfoKey: urls]
    }

    static func urls(from notification: Notification) -> [URL]? {
        if let urls = notification.userInfo?[archiveURLsUserInfoKey] as? [URL] {
            return urls
        }

        if let nsURLs = notification.userInfo?[archiveURLsUserInfoKey] as? [NSURL] {
            return nsURLs.map { $0 as URL }
        }

        return nil
    }
}
