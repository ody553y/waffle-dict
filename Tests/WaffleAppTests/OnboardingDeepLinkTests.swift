import Foundation
import Testing
@testable import WaffleApp

struct OnboardingDeepLinkTests {
    @Test func settingsDeepLinkStoresTargetTab() {
        let isolated = makeIsolatedDeepLinkUserDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }

        let router = SettingsTabRouter(defaults: isolated.defaults)
        router.route(to: .models)

        #expect(
            isolated.defaults.string(forKey: SettingsTabRouter.selectedTabDefaultsKey)
                == SettingsTab.models.rawValue
        )
    }

    @Test func microphoneAndAccessibilitySystemSettingsURLsMatchExpectedTargets() throws {
        #expect(
            try #require(OnboardingSystemSettingsLink.microphone.url?.absoluteString)
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
        #expect(
            try #require(OnboardingSystemSettingsLink.accessibility.url?.absoluteString)
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }
}

private func makeIsolatedDeepLinkUserDefaults() -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = "OnboardingDeepLinkTests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suiteName)!, suiteName)
}
