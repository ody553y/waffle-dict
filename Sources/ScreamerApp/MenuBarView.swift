import SwiftUI
import AVFoundation
import ScreamerCore

struct MenuBarView: View {
    @AppStorage("screamer.didDismissAccessibilityPrompt")
    private var didDismissAccessibilityPrompt = false

    @State private var workerStatus: String = "Checking…"
    @State private var dictationState: DictationState = .idle
    @State private var shouldShowMicrophoneSettingsButton = false
    @State private var shouldShowAccessibilityPrompt = false
    @State private var lastDeliveryMessage: String?
    @State private var isShowingFullTranscript = false
    @State private var resultAutoClearTask: Task<Void, Never>?

    private let workerClient: WorkerClient
    private let audioCaptureService: AudioCaptureService
    private let pasteHelper: PasteHelper
    private let permissionsService: PermissionsService

    init(
        workerClient: WorkerClient = WorkerClient(),
        audioCaptureService: AudioCaptureService = AudioCaptureService(),
        pasteHelper: PasteHelper = PasteHelper(),
        permissionsService: PermissionsService = PermissionsService()
    ) {
        self.workerClient = workerClient
        self.audioCaptureService = audioCaptureService
        self.pasteHelper = pasteHelper
        self.permissionsService = permissionsService
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("Worker: \(workerStatus)")
                    .font(.caption)
            }

            Divider()

            Button(recordingButtonLabel) {
                Task {
                    await handleRecordingButtonTap()
                }
            }
            .keyboardShortcut("r")
            .disabled(isTranscribing)

            if case .transcribing = dictationState {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing…")
                        .font(.caption)
                }
            }

            if case .success(let transcript) = dictationState {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    if let deliveryMessage = lastDeliveryMessage {
                        Text(deliveryMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView {
                        Text(displayTranscriptText(for: transcript))
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)

                    HStack(spacing: 10) {
                        if transcript.count > 200 {
                            Button(isShowingFullTranscript ? "Show Less" : "Show More") {
                                isShowingFullTranscript.toggle()
                            }
                            .font(.caption)
                        }

                        Button("Copy Again") {
                            copyTranscriptAgain(transcript)
                        }
                        .font(.caption)
                    }
                }
            }

            if case .error(let message) = dictationState {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if shouldShowMicrophoneSettingsButton {
                        Button("Open Microphone Settings") {
                            openMicrophoneSystemSettings()
                        }
                        .font(.caption)
                    }
                }
            }

            if shouldShowAccessibilityPrompt {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("To paste directly into the active app, enable Accessibility access for Screamer.")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        Button("Open Accessibility Settings") {
                            openAccessibilitySystemSettings()
                            dismissAccessibilityPrompt()
                        }
                        .font(.caption)
                        Button("Dismiss") {
                            dismissAccessibilityPrompt()
                        }
                        .font(.caption)
                    }
                }
            }

            Divider()

            Button("Settings…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 220)
        .task {
            await checkWorker()
        }
    }

    private enum DictationState: Equatable {
        case idle
        case recording
        case transcribing
        case success(String)
        case error(String)
    }

    private var recordingButtonLabel: String {
        switch dictationState {
        case .recording:
            return "Stop Recording"
        case .transcribing:
            return "Transcribing…"
        default:
            return "Start Recording"
        }
    }

    private var isTranscribing: Bool {
        if case .transcribing = dictationState {
            return true
        }
        return false
    }

    private var statusColor: Color {
        switch workerStatus {
        case "OK": return .green
        case "Checking…", "Model loading…": return .yellow
        default: return .red
        }
    }

    @MainActor
    private func handleRecordingButtonTap() async {
        if case .recording = dictationState {
            await stopAndTranscribe()
            return
        }

        await startRecording()
    }

    @MainActor
    private func startRecording() async {
        resultAutoClearTask?.cancel()
        resultAutoClearTask = nil
        isShowingFullTranscript = false
        lastDeliveryMessage = nil
        shouldShowMicrophoneSettingsButton = false

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
            dictationState = .recording
        } catch {
            dictationState = .error(userFacingMessage(for: error))
        }
    }

    @MainActor
    private func stopAndTranscribe() async {
        guard let recordingURL = audioCaptureService.stopRecording() else {
            dictationState = .error("No active recording was found.")
            return
        }

        dictationState = .transcribing

        do {
            let response = try await workerClient.transcribeFile(
                FileTranscriptionRequestPayload(
                    jobID: UUID().uuidString,
                    modelID: "small",
                    filePath: recordingURL.path,
                    languageHint: nil,
                    translateToEnglish: false
                )
            )

            let pasteResult = pasteHelper.copyAndPaste(response.text)
            updateAccessibilityPromptState(for: pasteResult)
            lastDeliveryMessage = deliveryMessage(for: pasteResult)
            isShowingFullTranscript = false
            audioCaptureService.cleanupScratchFile(recordingURL)
            dictationState = .success(response.text)
            scheduleResultAutoClear()
        } catch {
            lastDeliveryMessage = nil
            dictationState = .error(userFacingMessage(for: error))
            scheduleResultAutoClear()
        }
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

    @MainActor
    private func showMicrophonePermissionBlockedMessage() {
        dictationState = .error("Microphone access is blocked. Enable it in System Settings to record.")
        shouldShowMicrophoneSettingsButton = true
    }

    private func openMicrophoneSystemSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            )
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func displayTranscriptText(for transcript: String) -> String {
        guard transcript.count > 200, !isShowingFullTranscript else {
            return transcript
        }
        return "\(String(transcript.prefix(200)))…"
    }

    @MainActor
    private func scheduleResultAutoClear() {
        resultAutoClearTask?.cancel()
        resultAutoClearTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            if case .success = dictationState {
                dictationState = .idle
                lastDeliveryMessage = nil
                isShowingFullTranscript = false
            } else if case .error = dictationState {
                dictationState = .idle
            }
        }
    }

    @MainActor
    private func copyTranscriptAgain(_ transcript: String) {
        let result = pasteHelper.copyOnly(transcript)
        if result == .copiedOnly {
            lastDeliveryMessage = "Copied to clipboard"
        }
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

    @MainActor
    private func updateAccessibilityPromptState(for pasteResult: PasteHelper.Result) {
        guard pasteResult == .copiedOnly else { return }
        guard permissionsService.isAccessibilityGranted == false else { return }
        guard didDismissAccessibilityPrompt == false else { return }
        shouldShowAccessibilityPrompt = true
    }

    @MainActor
    private func dismissAccessibilityPrompt() {
        shouldShowAccessibilityPrompt = false
        didDismissAccessibilityPrompt = true
    }

    private func openAccessibilitySystemSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func checkWorker() async {
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
}
