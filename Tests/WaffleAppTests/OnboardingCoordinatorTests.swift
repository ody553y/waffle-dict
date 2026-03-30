import Foundation
import Testing
@testable import WaffleApp

struct OnboardingCoordinatorTests {
    @Test func freshInstallIsIncomplete() {
        let isolated = makeIsolatedUserDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }

        let coordinator = OnboardingCoordinator(defaults: isolated.defaults)

        #expect(coordinator.isCompleted() == false)
    }

    @Test func markCompletedStoresCurrentVersion() {
        let isolated = makeIsolatedUserDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }

        let coordinator = OnboardingCoordinator(defaults: isolated.defaults)
        coordinator.markCompleted()

        #expect(coordinator.isCompleted())
        #expect(isolated.defaults.integer(forKey: OnboardingCoordinator.completionVersionDefaultsKey) == OnboardingCoordinator.currentVersion)
    }

    @Test func incompleteWhenRequiredVersionIsHigherThanStoredVersion() {
        let isolated = makeIsolatedUserDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.suiteName) }

        let coordinator = OnboardingCoordinator(defaults: isolated.defaults)
        coordinator.markCompleted(version: 1)

        #expect(coordinator.isCompleted(requiredVersion: 2) == false)
    }
}

private func makeIsolatedUserDefaults() -> (defaults: UserDefaults, suiteName: String) {
    let suiteName = "OnboardingCoordinatorTests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suiteName)!, suiteName)
}
