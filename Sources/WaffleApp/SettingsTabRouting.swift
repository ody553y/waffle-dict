import Foundation

enum SettingsTab: String, Sendable {
    case general
    case models
    case ai
    case statistics
    case keyboard
}

struct SettingsTabRouter {
    static let selectedTabDefaultsKey = "settingsSelectedTab"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func route(to tab: SettingsTab) {
        defaults.set(tab.rawValue, forKey: Self.selectedTabDefaultsKey)
    }
}

enum OnboardingSystemSettingsLink {
    case microphone
    case accessibility

    var url: URL? {
        switch self {
        case .microphone:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            )
        case .accessibility:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        }
    }
}
