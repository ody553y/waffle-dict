import AppKit
import ScreamerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let hotkeyStorageKey = "globalHotkey"
    private static let lmStudioHostStorageKey = "lmStudioHost"
    private static let lmStudioPortStorageKey = "lmStudioPort"

    private var workerProcess: Process?
    let modelStore = ModelStore()
    let transcriptStore: TranscriptStore? = try? TranscriptStore()
    private(set) var lmStudioClient = LMStudioClient(
        configuration: AppDelegate.loadLMStudioConfiguration()
    )
    lazy var dictationController: DictationController = {
        DictationController(
            modelStore: modelStore,
            transcriptStore: transcriptStore,
            restartWorker: { [weak self] in
                guard let self else { return false }
                return await self.restartWorkerProcess()
            }
        )
    }()

    private let permissionsService = PermissionsService()
    private let dictationPanelController = DictationPanelController()
    private var activeHotkey = AppDelegate.loadStoredHotkey()
    private lazy var hotkeyService: HotkeyServiceProtocol = HotkeyService(hotkey: activeHotkey)
    private var hotkeyPermissionMonitorTask: Task<Void, Never>?

    var hotkeyDisplayValue: String {
        activeHotkey.displayValue
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        dictationPanelController.bind(to: dictationController)
        startHotkeyPermissionMonitoring()

        Task {
            _ = await restartWorkerProcess()
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

    func updateHotkey(_ hotkey: GlobalHotkey) {
        guard hotkey != activeHotkey else { return }

        activeHotkey = hotkey
        hotkeyService.updateHotkey(hotkey)
        if let json = hotkey.encodedJSONString() {
            UserDefaults.standard.set(json, forKey: Self.hotkeyStorageKey)
        }
        refreshHotkeyRegistration()
    }

    func refreshLMStudioClientConfiguration() {
        lmStudioClient = LMStudioClient(configuration: Self.loadLMStudioConfiguration())
    }

    private func restartWorkerProcess() async -> Bool {
        workerProcess?.terminate()
        workerProcess = nil

        do {
            let wp = WorkerProcess()
            workerProcess = try await wp.start()
            return true
        } catch {
            print("[Screamer] Worker failed to start: \(error)")
            return false
        }
    }

    private static func loadStoredHotkey() -> GlobalHotkey {
        guard
            let rawValue = UserDefaults.standard.string(forKey: hotkeyStorageKey),
            let hotkey = GlobalHotkey.decoded(from: rawValue)
        else {
            return .optionSpace
        }
        return hotkey
    }

    private static func loadLMStudioConfiguration() -> LMStudioConfiguration {
        let defaults = UserDefaults.standard

        let storedHost = defaults.string(forKey: lmStudioHostStorageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let host = (storedHost?.isEmpty == false) ? storedHost! : "127.0.0.1"

        let storedPort = defaults.string(forKey: lmStudioPortStorageKey) ?? "1234"
        let port = Int(storedPort) ?? 1234

        return LMStudioConfiguration(host: host, port: port)
    }
}
