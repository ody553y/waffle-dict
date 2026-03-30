import AppKit
import SwiftUI
import WaffleCore

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    let hotkeyDisplayValue: String
    let transcriptStore: TranscriptStore?
    @AppStorage("showPreviewAfterDictation")
    private var showPreviewAfterDictation = true
    @AppStorage("previewAutoDismissSeconds")
    private var previewAutoDismissSeconds = 10

    @ObservedObject var dictationController: DictationController
    @ObservedObject var modelStore: ModelStore
    @State private var isHoveringPreview = false
    @State private var previewDismissTask: Task<Void, Never>?
    @StateObject private var reviewQueueMenuState: ReviewQueueMenuState

    init(
        hotkeyDisplayValue: String,
        dictationController: DictationController,
        modelStore: ModelStore,
        transcriptStore: TranscriptStore?
    ) {
        self.hotkeyDisplayValue = hotkeyDisplayValue
        self.dictationController = dictationController
        self.modelStore = modelStore
        self.transcriptStore = transcriptStore
        _reviewQueueMenuState = StateObject(
            wrappedValue: ReviewQueueMenuState(store: transcriptStore)
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(
                    localizedFormat(
                        "menu.worker.status",
                        default: "Worker: %@",
                        comment: "Worker status line shown in menu bar popover",
                        workerStatusDisplayText
                    )
                )
                    .font(.caption)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(workerStatusAccessibilityLabel)

            HStack {
                Text(
                    localized(
                        "menu.model.title",
                        default: "Model:",
                        comment: "Model label shown in menu bar popover"
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    modelStore.selectedEntry?.displayName
                        ?? localized(
                            "menu.model.noneInstalled",
                            default: "None installed",
                            comment: "Placeholder shown when no models are installed"
                        )
                )
                    .font(.caption)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(
                localized(
                    "menu.model.hint",
                    default: "Currently selected transcription model",
                    comment: "Accessibility hint for the model row in menu bar"
                )
            )

            Divider()

            if modelStore.hasInstalledModels == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        localized(
                            "menu.model.missing",
                            default: "No model installed. Open Settings -> Models to download one.",
                            comment: "Guidance shown in menu bar when no models are installed"
                        )
                    )
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(
                        localized(
                            "action.openSettings",
                            default: "Open Settings",
                            comment: "Action title that opens the app settings window"
                        )
                    ) {
                        SettingsOpener.open(openSettings: { openSettings() })
                    }
                    .font(.caption)
                }
            }

            Button(recordingButtonLabel) {
                Task {
                    await dictationController.handleRecordButtonTap()
                }
            }
            .keyboardShortcut("r")
            .disabled(dictationController.isTranscribing || (modelStore.hasInstalledModels == false && dictationController.isRecording == false))
            .accessibilityLabel(recordingButtonAccessibilityLabel)

            if dictationController.isHotkeyActive == false {
                Text(
                    localizedFormat(
                        "menu.hotkey.inactive",
                        default: "Global hotkey %@ is inactive. Enable Accessibility access to use it.",
                        comment: "Message shown when the global hotkey is inactive",
                        hotkeyDisplayValue
                    )
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if case .transcribing = dictationController.state {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(
                        localized(
                            "status.transcribing",
                            default: "Transcribing…",
                            comment: "Status text shown while a recording is transcribing"
                        )
                    )
                        .font(.caption)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    localized(
                        "menu.transcribing.accessibility",
                        default: "Transcription in progress",
                        comment: "Accessibility label for transcribing status row"
                    )
                )
            }

            if case .success(let transcript) = dictationController.state {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    if let deliveryMessage = dictationController.lastDeliveryMessage {
                        Text(deliveryMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if showPreviewAfterDictation, let preview = dictationController.lastTranscriptPreview {
                        transcriptPreviewCard(preview)
                    } else if showPreviewAfterDictation {
                        ScrollView {
                            Text(displayTranscriptText(for: transcript))
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 100)
                    }
                }
            }

            if case .error(let message) = dictationController.state {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if dictationController.shouldShowMicrophoneSettingsButton {
                        Button(
                            localized(
                                "menu.microphoneSettings.open",
                                default: "Open Microphone Settings",
                                comment: "Action title to open macOS microphone privacy settings"
                            )
                        ) {
                            openMicrophoneSystemSettings()
                        }
                        .font(.caption)
                    }

                    if dictationController.canRetryLastTranscription {
                        Button(
                            localized(
                                "action.retry",
                                default: "Retry",
                                comment: "Action title to retry a failed transcription"
                            )
                        ) {
                            Task {
                                await dictationController.retryLastTranscription()
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            if dictationController.shouldShowAccessibilityPrompt {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        localized(
                            "menu.accessibilityPrompt.body",
                            default: "To paste directly into the active app, enable Accessibility access for Waffle.",
                            comment: "Message prompting the user to grant macOS Accessibility permission"
                        )
                    )
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        Button(
                            localized(
                                "menu.accessibilityPrompt.openSettings",
                                default: "Open Accessibility Settings",
                                comment: "Action title that opens macOS Accessibility privacy settings"
                            )
                        ) {
                            openAccessibilitySystemSettings()
                            dictationController.dismissAccessibilityPrompt()
                        }
                        .font(.caption)
                        Button(
                            localized(
                                "action.dismiss",
                                default: "Dismiss",
                                comment: "Generic action title for dismissing a prompt"
                            )
                        ) {
                            dictationController.dismissAccessibilityPrompt()
                        }
                        .font(.caption)
                    }
                }
            }

            Divider()

            Button(
                localized(
                    "menu.settings.button",
                    default: "Settings…",
                    comment: "Button title that opens settings from menu bar popover"
                )
            ) {
                SettingsOpener.open(openSettings: { openSettings() })
            }
            .keyboardShortcut(",")
            .help(
                localized(
                    "menu.settings.help",
                    default: "Settings (\u{2318},)",
                    comment: "Tooltip for settings button including keyboard shortcut"
                )
            )

            Button(
                localized(
                    "menu.history.button",
                    default: "History",
                    comment: "Button title that opens transcript history"
                )
            ) {
                openWindow(id: "transcript-history")
            }
            .keyboardShortcut("h")
            .help(
                localized(
                    "menu.history.help",
                    default: "History (\u{2318}H)",
                    comment: "Tooltip for history button including keyboard shortcut"
                )
            )

            Button(reviewQueueMenuState.reviewButtonTitle) {
                reviewQueueMenuState.isQueuePresented = true
            }
            .disabled(transcriptStore == nil)
            .help("Review Queue (\u{2318}\u{21E7}R)")

            Button(
                localized(
                    "action.quit",
                    default: "Quit",
                    comment: "Action title that quits the app"
                )
            ) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 240)
        .task {
            modelStore.refreshCatalog()
            await dictationController.checkWorker()
            reviewQueueMenuState.refreshBadgeCount()
        }
        .onChange(of: dictationController.lastTranscriptPreview) { _, newPreview in
            schedulePreviewAutoDismiss(for: newPreview)
        }
        .onChange(of: previewAutoDismissSeconds) { _, _ in
            schedulePreviewAutoDismiss(for: dictationController.lastTranscriptPreview)
        }
        .onChange(of: isHoveringPreview) { _, _ in
            schedulePreviewAutoDismiss(for: dictationController.lastTranscriptPreview)
        }
        .onDisappear {
            previewDismissTask?.cancel()
            previewDismissTask = nil
            isHoveringPreview = false
            dictationController.clearLastTranscriptPreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .waffleOpenReviewQueue)) { notification in
            reviewQueueMenuState.handleOpenQueueNotification(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reviewQueueMenuState.refreshBadgeCount()
        }
        .sheet(isPresented: $reviewQueueMenuState.isQueuePresented) {
            if let transcriptStore {
                ReviewQueueView(
                    store: transcriptStore,
                    onOpenInHistory: { transcriptID in
                        openWindow(id: "transcript-history")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            NotificationCenter.default.post(
                                name: .waffleSelectTranscriptInHistory,
                                object: nil,
                                userInfo: ["transcriptID": transcriptID]
                            )
                        }
                    },
                    onQueueChanged: {
                        reviewQueueMenuState.refreshBadgeCount()
                    }
                )
            } else {
                ContentUnavailableView(
                    "Review Queue Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Transcript history is unavailable.")
                )
                .padding()
            }
        }
    }

    private var recordingButtonLabel: String {
        switch dictationController.state {
        case .recording:
            return localized(
                "menu.recording.stop",
                default: "Stop Recording",
                comment: "Button title to stop an active recording"
            )
        case .transcribing:
            return localized(
                "status.transcribing",
                default: "Transcribing…",
                comment: "Status text shown while a recording is transcribing"
            )
        default:
            return localized(
                "menu.recording.start",
                default: "Start Recording",
                comment: "Button title to start recording"
            )
        }
    }

    private var recordingButtonAccessibilityLabel: String {
        switch dictationController.state {
        case .recording:
            return localized(
                "menu.recording.accessibility.stop",
                default: "Stop recording",
                comment: "Accessibility label for record button while recording is active"
            )
        case .transcribing:
            return localized(
                "menu.recording.accessibility.transcribing",
                default: "Transcribing",
                comment: "Accessibility label for record button while transcription is running"
            )
        default:
            return localized(
                "menu.recording.accessibility.start",
                default: "Start recording",
                comment: "Accessibility label for record button while idle"
            )
        }
    }

    private var statusColor: Color {
        switch dictationController.workerStatus {
        case "OK":
            return .green
        case "Checking…", "Model loading…":
            return .yellow
        default:
            return .red
        }
    }

    @ViewBuilder
    private func transcriptPreviewCard(_ preview: DictationController.TranscriptPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayPreviewText(preview.text))
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Text(previewMetadata(preview))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button(
                    localized(
                        "action.copy",
                        default: "Copy",
                        comment: "Generic action title to copy transcript text"
                    )
                ) {
                    dictationController.copyTranscriptAgain(preview.text)
                }
                .font(.caption)

                Button(
                    localized(
                        "menu.preview.openHistory",
                        default: "Open in History",
                        comment: "Button title in menu preview card to open the transcript in history"
                    )
                ) {
                    openHistory(for: preview)
                }
                .font(.caption)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
        .onHover { isHovering in
            isHoveringPreview = isHovering
        }
    }

    private func displayTranscriptText(for transcript: String) -> String {
        guard transcript.count > 200 else {
            return transcript
        }
        return "\(String(transcript.prefix(200)))…"
    }

    private func displayPreviewText(_ transcript: String) -> String {
        guard transcript.count > 200 else { return transcript }
        return "\(String(transcript.prefix(200)))…"
    }

    private func previewMetadata(_ preview: DictationController.TranscriptPreview) -> String {
        let durationText: String
        if let durationSeconds = preview.durationSeconds {
            durationText = String(format: "%.1fs", durationSeconds)
        } else {
            durationText = localized(
                "menu.preview.duration.unknown",
                default: "Unknown duration",
                comment: "Duration label shown when preview duration is unavailable"
            )
        }

        let timestamp = Self.timestampFormatter.string(from: preview.timestamp)
        return localizedFormat(
            "menu.preview.metadata",
            default: "%d words • %@ • %@ • %@",
            comment: "Transcript preview metadata line: words, duration, model, and timestamp",
            preview.wordCount,
            durationText,
            preview.modelID,
            timestamp
        )
    }

    private func schedulePreviewAutoDismiss(for preview: DictationController.TranscriptPreview?) {
        previewDismissTask?.cancel()
        previewDismissTask = nil

        guard showPreviewAfterDictation else {
            dictationController.clearLastTranscriptPreview()
            return
        }
        guard isHoveringPreview == false else { return }
        guard let preview else { return }
        guard previewAutoDismissSeconds > 0 else { return }

        previewDismissTask = Task {
            do {
                try await Task.sleep(for: .seconds(previewAutoDismissSeconds))
            } catch {
                return
            }
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                if dictationController.lastTranscriptPreview == preview {
                    dictationController.clearLastTranscriptPreview()
                }
            }
        }
    }

    private func openHistory(for preview: DictationController.TranscriptPreview) {
        openWindow(id: "transcript-history")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(
                name: .waffleSelectTranscriptInHistory,
                object: nil,
                userInfo: ["transcriptID": preview.transcriptID]
            )
        }
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

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var workerStatusAccessibilityLabel: String {
        switch dictationController.workerStatus {
        case "OK":
            return localized(
                "menu.worker.accessibility.running",
                default: "Worker running",
                comment: "Accessibility label when background worker is healthy"
            )
        default:
            return localized(
                "menu.worker.accessibility.stopped",
                default: "Worker stopped",
                comment: "Accessibility label when background worker is unavailable"
                )
        }
    }

    private var workerStatusDisplayText: String {
        switch dictationController.workerStatus {
        case "OK":
            return localized(
                "menu.worker.state.ok",
                default: "OK",
                comment: "Worker health state shown when worker is ready"
            )
        case "Checking…":
            return localized(
                "menu.worker.state.checking",
                default: "Checking…",
                comment: "Worker health state shown while checking worker health"
            )
        case "Model loading…":
            return localized(
                "menu.worker.state.modelLoading",
                default: "Model loading…",
                comment: "Worker health state shown while model is loading"
            )
        case "Offline":
            return localized(
                "menu.worker.state.offline",
                default: "Offline",
                comment: "Worker health state shown when worker is unavailable"
            )
        default:
            return dictationController.workerStatus
        }
    }
}
