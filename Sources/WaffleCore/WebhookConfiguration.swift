import Foundation

public struct WebhookConfiguration: Codable, Equatable, Sendable {
    public static let storageKey = "webhookConfiguration"

    public var isEnabled: Bool
    public var endpointURL: String
    public var hmacSecret: String
    public var includeSpeakerMap: Bool
    public var includeSegments: Bool

    public init(
        isEnabled: Bool = false,
        endpointURL: String = "",
        hmacSecret: String = "",
        includeSpeakerMap: Bool = true,
        includeSegments: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.endpointURL = endpointURL
        self.hmacSecret = hmacSecret
        self.includeSpeakerMap = includeSpeakerMap
        self.includeSegments = includeSegments
    }

    public var trimmedEndpointURL: String {
        endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var validatedEndpointURL: URL? {
        guard trimmedEndpointURL.isEmpty == false else { return nil }
        guard let url = URL(string: trimmedEndpointURL) else { return nil }
        guard url.scheme?.lowercased() == "https" else { return nil }
        guard url.host?.isEmpty == false else { return nil }
        return url
    }

    public var isDeliveryEnabled: Bool {
        isEnabled && validatedEndpointURL != nil
    }

    public static func load(
        userDefaults: UserDefaults = .standard,
        decoder: JSONDecoder = JSONDecoder()
    ) -> WebhookConfiguration {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return WebhookConfiguration()
        }

        do {
            return try decoder.decode(WebhookConfiguration.self, from: data)
        } catch {
            return WebhookConfiguration()
        }
    }

    public static func save(
        _ configuration: WebhookConfiguration,
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        guard let data = try? encoder.encode(configuration) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
