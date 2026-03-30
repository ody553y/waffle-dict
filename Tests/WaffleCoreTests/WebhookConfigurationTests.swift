import Foundation
import Testing
@testable import WaffleCore

@Suite(.serialized)
struct WebhookConfigurationTests {
    @Test func loadReturnsDefaultWhenStorageIsMissing() {
        let defaults = makeDefaults()

        let loaded = WebhookConfiguration.load(userDefaults: defaults)

        #expect(loaded == WebhookConfiguration())
    }

    @Test func saveLoadRoundTripPreservesAllFields() {
        let defaults = makeDefaults()
        let input = WebhookConfiguration(
            isEnabled: true,
            endpointURL: "https://hooks.example.com/transcripts",
            hmacSecret: "super-secret",
            includeSpeakerMap: false,
            includeSegments: true
        )

        WebhookConfiguration.save(input, userDefaults: defaults)
        let output = WebhookConfiguration.load(userDefaults: defaults)

        #expect(output == input)
    }

    @Test func httpEndpointFailsValidation() {
        let config = WebhookConfiguration(
            isEnabled: true,
            endpointURL: "http://hooks.example.com/transcripts",
            hmacSecret: "",
            includeSpeakerMap: true,
            includeSegments: false
        )

        #expect(config.validatedEndpointURL == nil)
    }

    @Test func emptyEndpointIsConsideredDisabled() {
        let config = WebhookConfiguration(
            isEnabled: true,
            endpointURL: "   ",
            hmacSecret: "",
            includeSpeakerMap: true,
            includeSegments: false
        )

        #expect(config.isDeliveryEnabled == false)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "WebhookConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
