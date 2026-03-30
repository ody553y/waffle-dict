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

    private struct PendingRetryTranscription: Sendable {
        let recordingURL: URL
        let modelID: String
        let languageHint: String?
    }

    private let workerClient: WorkerClient
    private let audioCaptureService: AudioCaptureService
    private let pasteHelper: PasteHelper
    private let permissionsService: PermissionsService
    private let transcriptStore: TranscriptStore?
    private let modelStore: ModelStore
    private let restartWorker: @Sendable () async -> Bool
    private var resultAutoClearTask: Task<Void, Never>?
    private var pendingRetryTranscription: PendingRetryTranscription?

    init(
        modelStore: ModelStore,
        workerClient: WorkerClient = WorkerClient(),
        audioCaptureService: AudioCaptureService = AudioCaptureService(),
        pasteHelper: PasteHelper = PasteHelper(),
        permissionsService: PermissionsService = PermissionsService(),
        transcriptStore: TranscriptStore? = try? TranscriptStore(),
        restartWorker: @escaping @Sendable () async -> Bool = { false }
    ) {
        self.modelStore = modelStore
        self.workerClient = workerClient
        self.audioCaptureService = audioCaptureService
        self.pasteHelper = pasteHelper
        self.permissionsService = permissionsService
        self.transcriptStore = transcriptStore
        self.restartWorker = restartWorker
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

    var canRetryLastTranscription: Bool {
        pendingRetryTranscription != nil && !isTranscribing
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
        clearPendingRetryTranscription(cleanupFile: true)
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

        guard let selectedModel = modelStore.selectedEntry else {
            audioCaptureService.cleanupScratchFile(recordingURL)
            state = .error("No model installed. Open Settings > Models to download one.")
            scheduleResultAutoClear()
            return
        }

        let languageHint = effectiveLanguageHint(for: selectedModel)
        await transcribeRecording(
            recordingURL: recordingURL,
            modelID: selectedModel.id,
            languageHint: languageHint
        )
    }

    func retryLastTranscription() async {
        guard let pendingRetryTranscription else { return }
        resultAutoClearTask?.cancel()
        resultAutoClearTask = nil
        lastDeliveryMessage = nil
        shouldShowMicrophoneSettingsButton = false

        await transcribeRecording(
            recordingURL: pendingRetryTranscription.recordingURL,
            modelID: pendingRetryTranscription.modelID,
            languageHint: pendingRetryTranscription.languageHint
        )
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
                lastDeliveryMessage = nil
                clearPendingRetryTranscription(cleanupFile: true)
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

    private func stringValue(for key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    private func effectiveLanguageHint(for selectedModel: ModelCatalogEntry) -> String? {
        if selectedModel.family == .parakeet {
            return "en"
        }

        let storedValue = stringValue(for: "languageHint")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let storedValue, storedValue.isEmpty == false else {
            return nil
        }
        return storedValue
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
                switch statusCode {
                case 400:
                    return "Selected model is not available in the worker."
                case 503:
                    return "Model is still loading. Try again in a moment."
                default:
                    return "Worker request failed (\(statusCode))."
                }
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "Transcription timed out. Try a shorter recording."
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return "Worker is not running. Restart Screamer."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private func transcribeRecording(
        recordingURL: URL,
        modelID: String,
        languageHint: String?
    ) async {
        state = .transcribing

        do {
            let response = try await workerClient.transcribeFile(
                FileTranscriptionRequestPayload(
                    jobID: UUID().uuidString,
                    modelID: modelID,
                    filePath: recordingURL.path,
                    languageHint: languageHint,
                    translateToEnglish: false
                )
            )

            saveTranscriptToHistory(
                text: response.text,
                modelID: modelID,
                languageHint: languageHint,
                durationSeconds: audioCaptureService.recordingDurationSeconds(for: recordingURL),
                segments: response.segments?.map {
                    TranscriptSegment(start: $0.start, end: $0.end, text: $0.text)
                }
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
                clearPendingRetryTranscription(cleanupFile: false)
                lastDeliveryMessage = nil
                state = .error("Transcribed, but could not paste into the active app.")
                scheduleResultAutoClear()
                return
            }

            audioCaptureService.cleanupScratchFile(recordingURL)
            clearPendingRetryTranscription(cleanupFile: false)
            lastDeliveryMessage = deliveryMessage(for: pasteResult)
            state = .success(response.text)
            scheduleResultAutoClear()
        } catch {
            pendingRetryTranscription = PendingRetryTranscription(
                recordingURL: recordingURL,
                modelID: modelID,
                languageHint: languageHint
            )
            lastDeliveryMessage = nil

            if await handleWorkerCrashAndRestartIfNeeded(for: error) {
                return
            }

            state = .error(userFacingMessage(for: error))
            scheduleResultAutoClear()
        }
    }

    private func handleWorkerCrashAndRestartIfNeeded(for error: Error) async -> Bool {
        guard shouldProbeWorkerHealth(after: error) else { return false }

        do {
            _ = try await workerClient.fetchHealth()
            return false
        } catch {
            state = .error("Worker crashed. Restarting…")
            workerStatus = "Offline"
            let didRestart = await restartWorker()
            if didRestart {
                await checkWorker()
            } else {
                state = .error("Worker crashed. Restart failed. Restart Screamer.")
            }
            scheduleResultAutoClear()
            return true
        }
    }

    private func shouldProbeWorkerHealth(after error: Error) -> Bool {
        if error is URLError {
            return true
        }

        if let workerError = error as? WorkerClientError,
           case .unexpectedStatusCode(let statusCode) = workerError {
            return statusCode >= 500
        }

        return false
    }

    private func clearPendingRetryTranscription(cleanupFile: Bool) {
        guard let pendingRetryTranscription else { return }
        self.pendingRetryTranscription = nil
        if cleanupFile {
            audioCaptureService.cleanupScratchFile(pendingRetryTranscription.recordingURL)
        }
    }

    private func saveTranscriptToHistory(
        text: String,
        modelID: String,
        languageHint: String?,
        durationSeconds: Double?,
        segments: [TranscriptSegment]?
    ) {
        guard let transcriptStore else { return }

        let record = TranscriptRecord(
            createdAt: Date(),
            sourceType: "dictation",
            sourceFileName: nil,
            modelID: modelID,
            languageHint: languageHint,
            durationSeconds: durationSeconds,
            text: text,
            segments: segments
        )

        Task.detached(priority: .utility) {
            do {
                _ = try transcriptStore.save(record)
            } catch {
                print("[Screamer] Failed to save transcript history: \(error)")
            }
        }
    }
}
