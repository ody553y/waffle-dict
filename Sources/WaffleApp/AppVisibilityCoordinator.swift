import AppKit
import Foundation

protocol AppActivationPolicyControlling {
    @MainActor
    func setActivationPolicy(_ policy: NSApplication.ActivationPolicy)
}

struct NSApplicationActivationPolicyController: AppActivationPolicyControlling {
    @MainActor
    func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        _ = NSApplication.shared.setActivationPolicy(policy)
    }
}

@MainActor
final class AppVisibilityCoordinator {
    static let showInDockAndAppSwitcherKey = "showInDockAndAppSwitcher"

    private let defaults: UserDefaults
    private let policyController: AppActivationPolicyControlling

    init(
        defaults: UserDefaults = .standard,
        policyController: AppActivationPolicyControlling = NSApplicationActivationPolicyController()
    ) {
        self.defaults = defaults
        self.policyController = policyController
    }

    func applyCurrentSetting() {
        let currentValue = defaults.bool(forKey: Self.showInDockAndAppSwitcherKey)
        apply(showInDockAndAppSwitcher: currentValue)
    }

    func update(showInDockAndAppSwitcher: Bool) {
        defaults.set(showInDockAndAppSwitcher, forKey: Self.showInDockAndAppSwitcherKey)
        apply(showInDockAndAppSwitcher: showInDockAndAppSwitcher)
    }

    private func apply(showInDockAndAppSwitcher: Bool) {
        let policy: NSApplication.ActivationPolicy = showInDockAndAppSwitcher ? .regular : .accessory
        policyController.setActivationPolicy(policy)
    }
}
