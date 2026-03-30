import Foundation
import Sparkle

@MainActor
final class UpdaterSettings: ObservableObject {
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?

    private var updaterController: SPUStandardUpdaterController?

    var currentVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           version.isEmpty == false {
            return version
        }
        return "dev"
    }

    var isUpdaterReady: Bool {
        updaterController != nil
    }

    var lastUpdateCheckDescription: String {
        guard let lastUpdateCheckDate else {
            return "Never"
        }
        return Self.lastCheckFormatter.string(from: lastUpdateCheckDate)
    }

    func attach(updaterController: SPUStandardUpdaterController?) {
        self.updaterController = updaterController
        refresh()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        refresh()
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            self.refresh()
        }
    }

    func refresh() {
        guard let updater = updaterController?.updater else {
            automaticallyChecksForUpdates = false
            lastUpdateCheckDate = nil
            return
        }

        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }

    private static let lastCheckFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
