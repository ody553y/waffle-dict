import AppKit
import Foundation
import Testing
@testable import WaffleApp

@MainActor
struct AppVisibilityCoordinatorTests {
    @Test func applyCurrentSettingUsesAccessoryPolicyByDefault() {
        let (defaults, suiteName) = makeDefaults()
        defer { removeDefaults(suiteName) }
        let policyController = RecordingPolicyController()
        let coordinator = AppVisibilityCoordinator(defaults: defaults, policyController: policyController)

        coordinator.applyCurrentSetting()

        #expect(policyController.recordedPolicies == [.accessory])
    }

    @Test func updateTruePersistsAndUsesRegularPolicy() {
        let (defaults, suiteName) = makeDefaults()
        defer { removeDefaults(suiteName) }
        let policyController = RecordingPolicyController()
        let coordinator = AppVisibilityCoordinator(defaults: defaults, policyController: policyController)

        coordinator.update(showInDockAndAppSwitcher: true)

        #expect(defaults.bool(forKey: AppVisibilityCoordinator.showInDockAndAppSwitcherKey))
        #expect(policyController.recordedPolicies == [.regular])
    }

    @Test func updateFalsePersistsAndUsesAccessoryPolicy() {
        let (defaults, suiteName) = makeDefaults()
        defaults.set(true, forKey: AppVisibilityCoordinator.showInDockAndAppSwitcherKey)
        defer { removeDefaults(suiteName) }
        let policyController = RecordingPolicyController()
        let coordinator = AppVisibilityCoordinator(defaults: defaults, policyController: policyController)

        coordinator.update(showInDockAndAppSwitcher: false)

        #expect(defaults.bool(forKey: AppVisibilityCoordinator.showInDockAndAppSwitcherKey) == false)
        #expect(policyController.recordedPolicies == [.accessory])
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "AppVisibilityCoordinatorTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName) ?? .standard, suiteName)
    }

    private func removeDefaults(_ suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class RecordingPolicyController: AppActivationPolicyControlling {
    private(set) var recordedPolicies: [NSApplication.ActivationPolicy] = []

    func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        recordedPolicies.append(policy)
    }
}
