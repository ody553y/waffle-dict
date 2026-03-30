import Foundation

final class OnboardingCoordinator {
    static let completionVersionDefaultsKey = "onboardingCompletionVersion"
    static let currentVersion = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isCompleted(requiredVersion: Int = currentVersion) -> Bool {
        defaults.integer(forKey: Self.completionVersionDefaultsKey) >= requiredVersion
    }

    func markCompleted(version: Int = currentVersion) {
        defaults.set(version, forKey: Self.completionVersionDefaultsKey)
    }
}
