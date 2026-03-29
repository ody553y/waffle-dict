import Foundation
import ScreamerCore
import Combine

@MainActor
final class DictationController: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case success(String)
        case error(String)
    }

    @Published private(set) var workerStatus: String = "Checking…"
    @Published private(set) var state: State = .idle
    @Published private(set) var shouldShowMicrophoneSettingsButton = false
    @Published private(set) var shouldShowAccessibilityPrompt = false
    @Published private(set) var lastDeliveryMessage: String?
    @Published private(set) var isHotkeyActive = false

    private let workerClient: WorkerClient
    private let audioCaptureService: AudioCaptureService
    private let pasteHelper: PasteHelper
    private let permissionsService: PermissionsService
    private let modelStore: ModelStore
    private var resultAutoClearTask: Task<Void, Never>?

    init(
        modelStore: ModelStore,
        workerClient: WorkerClient = WorkerClient(),
        audioCaptureService: AudioCaptureService = AudioCaptureService(),
        pasteHelper: PasteHelper = PasteHelper(),
        permissionsService: PermissionsService = PermissionsService()
    ) {
        self.modelStore = modelStore
        self.workerClient = workerClient
        self.audioCaptureService = audioCaptureService
        self.pasteHelper = pasteHelper
        self.permissionsService = permissionsService
    }

    var isTranscribing: Bool {
        if case .transcribing = state {
            return true
        }
        return false
    }

    var isRecording: Bool {
        if case .recording = state {
            return true
        }
        return false
    }

    func updateHotkeyActive(_ isActive: Bool) {
        isHotkeyActive = isActive
    }

    func checkWorker() async {
        do {
            let health = try await workerClient.fetchHealth()
            if health.status == "ok" {
                workerStatus = health.modelLoaded ? "OK" : "Model loading…"
            } else {
                workerStatus = health.status
            }
        } catch {
            workerStatus = "Offline"
        }
    }

    func handleRecordButtonTap() async {
        if isRecording {
            await stopAndTranscribe()
            return
        }

        await startRecording()
    }

    func handleHotkeyPress() async {
        if isTranscribing {
            return
        }

        if isRecording {
            await stopAndTranscribe()
            return
        }

        await startRecording()
    }

    func cancelRecordingFromEscape() {
        guard isRecording else { return }
        resultAutoClearTask?.cancel()
        resultAutoClearTask = nil
        shouldShowAccessibilityPrompt = false
        shouldShowMicrophoneSettingsButton = false
        lastDeliveryMessage = nil
        audioCaptureService.cancelRecording()
        state = .idle
    }

    func copyTranscriptAgain(_ transcript: String) {
        let result = pasteHelper.copyOnly(transcript)
        if result == .copiedOnly {
            lastDeliveryMessage = "Copied to clipboard"
        }
    }

    func dismissAccessibilityPrompt() {
        shouldShowAccessibilityPrompt = false
        UserDefaults.standard.set(true, forKey: "screamer.didDismissAccessibilityPrompt")
    }

    private func startRecording() async {
        resultAutoClearTask?.cancel()
        resultAutoClearTask = nil
        lastDeliveryMessage = nil
        shouldShowMicrophoneSettingsButton = false

        guard modelStore.hasInstalledModels else {
            state = .error("No model installed. Open Settings > Models to download one.")
            scheduleResultAutoClear()
            return
        }

        switch audioCaptureService.microphoneAuthorizationStatus {
        case .authorized:
            break
        case .notDetermined:
            let granted = await audioCaptureService.requestPermission()
            guard granted else {
                showMicrophonePermissionBlockedMessage()
                return
            }
        case .denied, .restricted:
            showMicrophonePermissionBlockedMessage()
            return
        @unknown default:
            showMicrophonePermissionBlockedMessage()
            return
        }

        do {
            _ = try audioCaptureService.startRecording()
            state = .recording
        } catch {
            state = .error(userFacingMessage(for: error))
            scheduleResultAutoClear()
        }
    }

    private func stopAndTranscribe() async {
        guard let recordingURL = audioCaptureService.stopRecording() else {
            state = .error("No active recording was found.")
            scheduleResultAutoClear()
            return
        }

        state = .transcribing

        do {
            guard let selectedModel = modelStore.selectedEntry else {
                state = .error("No model installed. Open Settings > Models to download one.")
                scheduleResultAutoClear()
                return
            }

            let response = try await workerClient.transcribeFile(
                FileTranscriptionRequestPayload(
                    jobID: UUID().uuidString,
                    modelID: selectedModel.id,
                    filePath: recordingURL.path,
                    languageHint: nil,
                    translateToEnglish: false
                )
            )

            let pasteIntoActiveApp = value(for: "pasteIntoActiveApp", defaultValue: true)
            let copyToClipboardAsFallback = value(for: "copyToClipboardAsFallback", defaultValue: true)

            let pasteResult: PasteHelper.Result
            if pasteIntoActiveApp {
                pasteResult = pasteHelper.copyAndPaste(response.text)
            } else {
                pasteResult = pasteHelper.copyOnly(response.text)
            }

            if pasteIntoActiveApp {
                updateAccessibilityPromptState(for: pasteResult)
            } else {
                shouldShowAccessibilityPrompt = false
            }

            if pasteIntoActiveApp && copyToClipboardAsFallback == false && pasteResult == .copiedOnly {
                audioCaptureService.cleanupScratchFile(recordingURL)
                lastDeliveryMessage = nil
                state = .error("Transcribed, but could not paste into the active app.")
                scheduleResultAutoClear()
                return
            }

            audioCaptureService.cleanupScratchFile(recordingURL)
            lastDeliveryMessage = deliveryMessage(for: pasteResult)
            state = .success(response.text)
            scheduleResultAutoClear()
        } catch {
            audioCaptureService.cleanupScratchFile(recordingURL)
            lastDeliveryMessage = nil
            state = .error(userFacingMessage(for: error))
            scheduleResultAutoClear()
        }
    }

    private func scheduleResultAutoClear() {
        resultAutoClearTask?.cancel()
        resultAutoClearTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            if case .success = state {
                state = .idle
                lastDeliveryMessage = nil
            } else if case .error = state {
                state = .idle
            }
        }
    }

    private func showMicrophonePermissionBlockedMessage() {
        state = .error("Microphone access is blocked. Enable it in System Settings to record.")
        shouldShowMicrophoneSettingsButton = true
    }

    private func updateAccessibilityPromptState(for pasteResult: PasteHelper.Result) {
        guard pasteResult == .copiedOnly else { return }
        guard permissionsService.isAccessibilityGranted == false else { return }
        let didDismissPrompt = UserDefaults.standard.bool(forKey: "screamer.didDismissAccessibilityPrompt")
        guard didDismissPrompt == false else { return }
        shouldShowAccessibilityPrompt = true
    }

    private func deliveryMessage(for pasteResult: PasteHelper.Result) -> String {
        switch pasteResult {
        case .pastedAndCopied:
            return "Pasted into app"
        case .copiedOnly:
            return "Copied to clipboard"
        case .copyFailed:
            return "Transcribed, but copy failed"
        }
    }

    private func value(for key: String, defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    private func userFacingMessage(for error: Error) -> String {
        if let audioError = error as? AudioCaptureError {
            switch audioError {
            case .permissionDenied:
                return "Microphone access is required to start recording."
            case .noInputDevice:
                return "No microphone input device is available."
            case .recordingFailed(let detail):
                return "Recording failed: \(detail)"
            }
        }

        if let workerError = error as? WorkerClientError {
            switch workerError {
            case .unexpectedStatusCode(let statusCode):
                return "Worker request failed (\(statusCode))."
            }
        }

        return error.localizedDescription
    }
}
