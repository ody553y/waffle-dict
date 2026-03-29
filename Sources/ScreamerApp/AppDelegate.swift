import AppKit
import ScreamerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var workerProcess: Process?
    let modelStore = ModelStore()
    lazy var dictationController = DictationController(modelStore: modelStore)

    private let permissionsService = PermissionsService()
    private let dictationPanelController = DictationPanelController()
    private let hotkeyService: HotkeyServiceProtocol = HotkeyService()
    private var hotkeyPermissionMonitorTask: Task<Void, Never>?

    var hotkeyDisplayValue: String {
        hotkeyService.hotkeyDisplayValue
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        dictationPanelController.bind(to: dictationController)
        startHotkeyPermissionMonitoring()

        Task {
            do {
                let wp = WorkerProcess()
                workerProcess = try await wp.start()
            } catch {
                print("[Screamer] Worker failed to start: \(error)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyPermissionMonitorTask?.cancel()
        hotkeyPermissionMonitorTask = nil
        hotkeyService.stop()
        dictationPanelController.teardown()
        workerProcess?.terminate()
    }

    private func startHotkeyPermissionMonitoring() {
        hotkeyPermissionMonitorTask?.cancel()
        hotkeyPermissionMonitorTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                refreshHotkeyRegistration()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refreshHotkeyRegistration() {
        guard permissionsService.isAccessibilityGranted else {
            hotkeyService.stop()
            dictationController.updateHotkeyActive(false)
            return
        }

        if hotkeyService.isRunning {
            dictationController.updateHotkeyActive(true)
            return
        }

        let started = hotkeyService.start { [weak self] in
            Task { @MainActor in
                await self?.dictationController.handleHotkeyPress()
            }
        }
        dictationController.updateHotkeyActive(started)
    }
}
