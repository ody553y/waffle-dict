import Foundation

public struct WebhookDeliveryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var deliveredAt: Date
    public var event: String
    public var statusCode: Int?
    public var succeeded: Bool
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        deliveredAt: Date = Date(),
        event: String,
        statusCode: Int?,
        succeeded: Bool,
        errorMessage: String?
    ) {
        self.id = id
        self.deliveredAt = deliveredAt
        self.event = event
        self.statusCode = statusCode
        self.succeeded = succeeded
        self.errorMessage = errorMessage
    }
}

public final class WebhookDeliveryLog: @unchecked Sendable {
    public static let storageKey = "webhookDeliveryLog"
    public static let maxEntries = 10

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
    }

    public func load() -> [WebhookDeliveryEntry] {
        guard let data = userDefaults.data(forKey: Self.storageKey) else {
            return []
        }

        do {
            return try decoder.decode([WebhookDeliveryEntry].self, from: data)
        } catch {
            return []
        }
    }

    public func append(_ entry: WebhookDeliveryEntry) {
        var entries = load()
        entries.append(entry)

        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }

        save(entries)
    }

    public func clear() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }

    private func save(_ entries: [WebhookDeliveryEntry]) {
        guard let data = try? encoder.encode(entries) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }
}
