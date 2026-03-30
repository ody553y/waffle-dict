import AppKit
import WaffleCore
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let hotkeyStorageKey = "globalHotkey"
    private static let lmStudioHostStorageKey = "lmStudioHost"
    private static let lmStudioPortStorageKey = "lmStudioPort"

    private var workerProcess: Process?
    private var updaterController: SPUStandardUpdaterController?
    let updaterSettings = UpdaterSettings()
    let modelStore = ModelStore()
    let transcriptStore: TranscriptStore? = {
        let store = try? TranscriptStore()
        TranscriptIntentBridge.shared.transcriptStore = store
        return store
    }()
    private(set) var lmStudioClient = LMStudioClient(
        configuration: AppDelegate.loadLMStudioConfiguration()
    )
    lazy var dictationController: DictationController = {
        let controller = DictationController(
            modelStore: modelStore,
            transcriptStore: transcriptStore,
            restartWorker: { [weak self] in
                guard let self else { return false }
                return await self.restartWorkerProcess()
            }
        )
        DictationIntentBridge.shared.dictationController = controller
        TranscriptIntentBridge.shared.transcriptStore = transcriptStore
        return controller
    }()

    private let permissionsService = PermissionsService()
    private let dictationPanelController = DictationPanelController()
    private var activeHotkey = AppDelegate.loadStoredHotkey()
    private lazy var hotkeyService: HotkeyServiceProtocol = HotkeyService(hotkey: activeHotkey)
    private var hotkeyPermissionMonitorTask: Task<Void, Never>?
    private var startupBeganAtUptimeNanos: UInt64?
    private var didLogStartupCompletion = false
    private var openWindowByID: ((String) -> Void)?
    private let appVisibilityCoordinator = AppVisibilityCoordinator()

    var hotkeyDisplayValue: String {
        activeHotkey.displayValue
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startupBeganAtUptimeNanos = DispatchTime.now().uptimeNanoseconds
        appVisibilityCoordinator.applyCurrentSetting()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterSettings.attach(updaterController: updaterController)

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
        DictationIntentBridge.shared.dictationController = nil
        TranscriptIntentBridge.shared.transcriptStore = nil
        updaterSettings.attach(updaterController: nil)
        updaterController = nil
        workerProcess?.terminate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard flag == false else { return false }
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindowByID?("control-center")
        return true
    }

    func setWindowOpener(_ handler: @escaping (String) -> Void) {
        openWindowByID = handler
    }

    func setShowInDockAndAppSwitcher(_ value: Bool) {
        appVisibilityCoordinator.update(showInDockAndAppSwitcher: value)
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
            recordStartupCompletionIfNeeded()
            return true
        } catch {
            print("[Waffle] Worker failed to start: \(error)")
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
        let host = (storedHost?.isEmpty == false) ? storedHost ?? "127.0.0.1" : "127.0.0.1"

        let storedPort = defaults.string(forKey: lmStudioPortStorageKey) ?? "1234"
        let port = Int(storedPort) ?? 1234

        return LMStudioConfiguration(host: host, port: port)
    }

    private func recordStartupCompletionIfNeeded() {
        guard didLogStartupCompletion == false else { return }
        guard let startupBeganAtUptimeNanos else { return }

        let now = DispatchTime.now().uptimeNanoseconds
        guard now > startupBeganAtUptimeNanos else { return }

        didLogStartupCompletion = true
        let startupDurationSeconds = Double(now - startupBeganAtUptimeNanos) / 1_000_000_000
        PerformanceMetrics.shared.record("app.startup", durationSeconds: startupDurationSeconds)

        let startupMilliseconds = Int((startupDurationSeconds * 1_000).rounded())
        print("[waffle] startup completed in \(startupMilliseconds)ms")
    }
}
