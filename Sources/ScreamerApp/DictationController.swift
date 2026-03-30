import Foundation
import ScreamerCore
import Combine
import OSLog

@MainActor
final class DictationController: ObservableObject {
    private static let defaultAutoSummarizePrompt =
        "Summarize this transcript in 3–5 bullet points, focusing on key decisions and action items."
    private static let log = Logger(
        subsystem: "com.screamer.app",
        category: "DictationController"
    )

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
    @Published private(set) var lastTranscriptPreview: TranscriptPreview?

    private struct PendingRetryTranscription: Sendable {
        let recordingURL: URL
        let modelID: String
        let languageHint: String?
    }

    struct TranscriptPreview: Sendable, Equatable {
        let text: String
        let wordCount: Int
        let durationSeconds: Double?
        let modelID: String
        let timestamp: Date
        let transcriptID: Int64
    }

    private let workerClient: WorkerClient
    private let audioCaptureService: AudioCaptureService
    private let pasteHelper: PasteHelper
    private let permissionsService: PermissionsService
    private let transcriptStore: TranscriptStore?
    private let speakerProfileStore: SpeakerProfileStore?
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
        if let transcriptStore {
            self.speakerProfileStore = SpeakerProfileStore(databaseQueue: transcriptStore.databaseQueue)
        } else {
            self.speakerProfileStore = nil
        }
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
            lastDeliveryMessage = localized(
                "status.copiedToClipboard",
                default: "Copied to clipboard",
                comment: "Status message shown when transcript is copied to clipboard"
            )
        }
    }

    func clearLastTranscriptPreview() {
        lastTranscriptPreview = nil
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
            state = .error(
                localized(
                    "error.model.missing",
                    default: "No model installed. Open Settings > Models to download one.",
                    comment: "Error shown when recording starts without any installed model"
                )
            )
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
            state = .error(
                localized(
                    "error.recording.noneActive",
                    default: "No active recording was found.",
                    comment: "Error shown when stop is requested without an active recording"
                )
            )
            scheduleResultAutoClear()
            return
        }

        guard let selectedModel = modelStore.selectedEntry else {
            audioCaptureService.cleanupScratchFile(recordingURL)
            state = .error(
                localized(
                    "error.model.missing",
                    default: "No model installed. Open Settings > Models to download one.",
                    comment: "Error shown when recording completes but no model is selected"
                )
            )
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
        state = .error(
            localized(
                "error.microphone.blocked",
                default: "Microphone access is blocked. Enable it in System Settings to record.",
                comment: "Error shown when microphone permission is blocked"
            )
        )
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
            return localized(
                "status.pastedIntoApp",
                default: "Pasted into app",
                comment: "Status message when transcript is pasted into the active app"
            )
        case .copiedOnly:
            return localized(
                "status.copiedToClipboard",
                default: "Copied to clipboard",
                comment: "Status message when transcript is only copied to clipboard"
            )
        case .copyFailed:
            return localized(
                "error.copy.failed",
                default: "Transcribed, but copy failed",
                comment: "Error message when transcription succeeds but clipboard copy fails"
            )
        }
    }

    private func value(for key: String, defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    private func shouldRetainAudioRecordings() -> Bool {
        value(for: "retainAudioRecordings", defaultValue: false)
    }

    private func stringValue(for key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    private func shouldAutoSummarize() -> Bool {
        value(for: "autoSummarizeEnabled", defaultValue: false)
    }

    private var selectedLLMModelID: String? {
        let trimmed = stringValue(for: "lmStudioModelID")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, trimmed.isEmpty == false else { return nil }
        return trimmed
    }

    private func autoSummarizePrompt() -> String {
        let trimmed = stringValue(for: "autoSummarizePrompt")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, trimmed.isEmpty == false else {
            return Self.defaultAutoSummarizePrompt
        }
        return trimmed
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
                return localized(
                    "error.microphone.required",
                    default: "Microphone access is required to start recording.",
                    comment: "Error shown when microphone permission is denied"
                )
            case .noInputDevice:
                return localized(
                    "error.microphone.noInputDevice",
                    default: "No microphone input device is available.",
                    comment: "Error shown when no microphone input device is detected"
                )
            case .recordingFailed(let detail):
                return localizedFormat(
                    "error.recording.failedWithDetail",
                    default: "Recording failed: %@",
                    comment: "Error shown when recording fails with a detailed message",
                    detail
                )
            }
        }

        if let workerError = error as? WorkerClientError {
            switch workerError {
            case .unexpectedStatusCode(let statusCode):
                switch statusCode {
                case 400:
                    return localized(
                        "error.worker.modelUnavailable",
                        default: "Selected model is not available in the worker.",
                        comment: "Error shown when selected model cannot be used by worker"
                    )
                case 503:
                    return localized(
                        "error.worker.modelLoading",
                        default: "Model is still loading. Try again in a moment.",
                        comment: "Error shown when worker model is still loading"
                    )
                default:
                    return localizedFormat(
                        "error.worker.requestFailed",
                        default: "Worker request failed (%d).",
                        comment: "Error shown when worker request fails with status code",
                        statusCode
                    )
                }
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return localized(
                    "error.transcription.timeout",
                    default: "Transcription timed out. Try a shorter recording.",
                    comment: "Error shown when transcription request times out"
                )
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return localized(
                    "error.worker.notRunning",
                    default: "Worker is not running. Restart Screamer.",
                    comment: "Error shown when worker cannot be reached over the network"
                )
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
        let transcriptionStartedAt = DispatchTime.now().uptimeNanoseconds
        state = .transcribing

        do {
            let response = try await workerClient.transcribeFile(
                FileTranscriptionRequestPayload(
                    jobID: UUID().uuidString,
                    modelID: modelID,
                    filePath: recordingURL.path,
                    languageHint: languageHint,
                    translateToEnglish: false,
                    diarize: false
                )
            )

            let durationSeconds = audioCaptureService.recordingDurationSeconds(for: recordingURL)
            let savedRecord = await saveTranscriptToHistory(
                text: response.text,
                modelID: modelID,
                languageHint: languageHint,
                durationSeconds: durationSeconds,
                segments: response.segments?.map {
                    TranscriptSegment(start: $0.start, end: $0.end, text: $0.text, speaker: $0.speaker)
                }
            )
            processSpeakerEmbeddingsIfAvailable(
                transcript: savedRecord,
                speakerEmbeddings: response.speakerEmbeddings
            )
            await finalizeRecordingStorage(recordingURL: recordingURL, savedRecord: savedRecord)
            triggerAutoSummarizeIfNeeded(for: savedRecord)

            if value(for: "showPreviewAfterDictation", defaultValue: true),
               let transcriptID = savedRecord?.id {
                lastTranscriptPreview = TranscriptPreview(
                    text: response.text,
                    wordCount: Self.wordCount(in: response.text),
                    durationSeconds: durationSeconds,
                    modelID: modelID,
                    timestamp: savedRecord?.createdAt ?? Date(),
                    transcriptID: transcriptID
                )
            } else if value(for: "showPreviewAfterDictation", defaultValue: true) == false {
                lastTranscriptPreview = nil
            }

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
                clearPendingRetryTranscription(cleanupFile: false)
                lastDeliveryMessage = nil
                state = .error(
                    localized(
                        "error.paste.failed",
                        default: "Transcribed, but could not paste into the active app.",
                        comment: "Error shown when transcription succeeds but paste into active app fails"
                    )
                )
                scheduleResultAutoClear()
                return
            }

            clearPendingRetryTranscription(cleanupFile: false)
            lastDeliveryMessage = deliveryMessage(for: pasteResult)
            state = .success(response.text)
            PerformanceMetrics.shared.record(
                "dictation.transcription.e2e",
                durationSeconds: elapsedDurationSeconds(since: transcriptionStartedAt)
            )
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
            state = .error(
                localized(
                    "error.worker.crashedRestarting",
                    default: "Worker crashed. Restarting…",
                    comment: "Error status shown while restarting crashed worker"
                )
            )
            workerStatus = "Offline"
            let didRestart = await restartWorker()
            if didRestart {
                await checkWorker()
            } else {
                state = .error(
                    localized(
                        "error.worker.crashedRestartFailed",
                        default: "Worker crashed. Restart failed. Restart Screamer.",
                        comment: "Error shown when worker restart attempt fails"
                    )
                )
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
    ) async -> TranscriptRecord? {
        guard let transcriptStore else { return nil }

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

        return await Task.detached(priority: .utility) {
            do {
                return try transcriptStore.save(record)
            } catch {
                print("[Screamer] Failed to save transcript history: \(error)")
                return nil
            }
        }.value
    }

    private func finalizeRecordingStorage(recordingURL: URL, savedRecord: TranscriptRecord?) async {
        guard shouldRetainAudioRecordings() else {
            audioCaptureService.cleanupScratchFile(recordingURL)
            return
        }

        guard
            let transcriptStore,
            let transcriptID = savedRecord?.id
        else {
            audioCaptureService.cleanupScratchFile(recordingURL)
            return
        }

        do {
            let archivedURL = try audioCaptureService.archiveRecording(
                from: recordingURL,
                transcriptID: transcriptID
            )

            _ = try await Task.detached(priority: .utility) {
                try transcriptStore.updateAudioFilePath(id: transcriptID, path: archivedURL.path)
            }.value
        } catch {
            print("[Screamer] Failed to archive retained audio: \(error)")
            audioCaptureService.cleanupScratchFile(recordingURL)
        }
    }

    private func triggerAutoSummarizeIfNeeded(for transcript: TranscriptRecord?) {
        guard shouldAutoSummarize() else { return }
        guard let transcript else { return }
        guard selectedLLMModelID != nil else { return }

        Task {
            await performAutoSummarize(transcript: transcript)
        }
    }

    private func performAutoSummarize(transcript: TranscriptRecord) async {
        guard let transcriptID = transcript.id else { return }
        guard let modelID = selectedLLMModelID else { return }
        guard let actionService = makeTranscriptActionService() else {
            Self.log.debug("Auto-summarize skipped because LM Studio is not configured")
            return
        }

        let prompt = autoSummarizePrompt()

        do {
            let result = try await actionService.perform(
                action: .customPrompt(prompt: prompt),
                on: transcript,
                modelID: modelID
            )

            guard let transcriptStore else { return }
            _ = try await Task.detached(priority: .utility) {
                try transcriptStore.saveAction(
                    TranscriptActionRecord(
                        transcriptID: transcriptID,
                        createdAt: result.createdAt,
                        actionType: "auto_summarise",
                        actionInput: prompt,
                        llmModelID: result.modelUsed,
                        resultText: result.resultText
                    )
                )
            }.value
        } catch {
            Self.log.debug(
                "Auto-summarize failed for transcript \(transcriptID, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func makeTranscriptActionService() -> TranscriptActionService? {
        guard
            let host = stringValue(for: "lmStudioHost")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            host.isEmpty == false,
            let portText = stringValue(for: "lmStudioPort"),
            let port = Int(portText),
            port > 0
        else {
            return nil
        }

        let client = LMStudioClient(configuration: LMStudioConfiguration(host: host, port: port))
        return TranscriptActionService(lmStudioClient: client)
    }

    private func processSpeakerEmbeddingsIfAvailable(
        transcript: TranscriptRecord?,
        speakerEmbeddings: [String: [Float]?]?
    ) {
        guard let transcriptStore else { return }
        guard let speakerProfileStore else { return }
        guard let transcriptID = transcript?.id else { return }
        let normalizedEmbeddings = normalizedSpeakerEmbeddings(from: speakerEmbeddings)
        guard normalizedEmbeddings.isEmpty == false else { return }

        let threshold = speakerMatchThreshold()
        let logger = Self.log

        Task.detached(priority: .utility) {
            do {
                try transcriptStore.saveEmbeddings(normalizedEmbeddings, transcriptID: transcriptID)
                for embedding in normalizedEmbeddings.values {
                    _ = try speakerProfileStore.matchOrCreateProfile(for: embedding, threshold: threshold)
                }
            } catch {
                logger.debug(
                    "Speaker embedding persistence failed for transcript \(transcriptID, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func normalizedSpeakerEmbeddings(
        from speakerEmbeddings: [String: [Float]?]?
    ) -> [String: [Float]] {
        guard let speakerEmbeddings else { return [:] }
        var normalized: [String: [Float]] = [:]

        for (speakerLabel, embedding) in speakerEmbeddings {
            let normalizedLabel = speakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedLabel.isEmpty == false else { continue }
            guard let embedding, embedding.isEmpty == false else { continue }
            normalized[normalizedLabel] = embedding
        }

        return normalized
    }

    private func speakerMatchThreshold() -> Float {
        let defaults = UserDefaults.standard
        let key = "speakerMatchThreshold"
        if defaults.object(forKey: key) == nil {
            return 0.85
        }
        let threshold = defaults.double(forKey: key)
        return Float(min(max(threshold, 0.70), 0.99))
    }

    private func elapsedDurationSeconds(since startedAt: UInt64) -> Double {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now > startedAt else { return 0 }
        return Double(now - startedAt) / 1_000_000_000
    }

    private static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

extension Notification.Name {
    static let screamerSelectTranscriptInHistory = Notification.Name("screamer.selectTranscriptInHistory")
    static let screamerImportTranscriptArchive = Notification.Name("screamer.importTranscriptArchive")
}
