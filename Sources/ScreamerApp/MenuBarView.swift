import SwiftUI

struct MenuBarView: View {
    @AppStorage("showTranscriptInMenuAfterTranscription")
    private var showTranscriptInMenuAfterTranscription = true

    @ObservedObject var dictationController: DictationController
    @ObservedObject var modelStore: ModelStore
    @State private var isShowingFullTranscript = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("Worker: \(dictationController.workerStatus)")
                    .font(.caption)
            }

            HStack {
                Text("Model:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(modelStore.selectedEntry?.displayName ?? "None installed")
                    .font(.caption)
            }

            Divider()

            if modelStore.hasInstalledModels == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No model installed. Open Settings -> Models to download one.")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Open Settings") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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

            if dictationController.isHotkeyActive == false {
                Text("Global hotkey ⌥Space is inactive. Enable Accessibility access to use it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if case .transcribing = dictationController.state {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing…")
                        .font(.caption)
                }
            }

            if case .success(let transcript) = dictationController.state {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    if let deliveryMessage = dictationController.lastDeliveryMessage {
                        Text(deliveryMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if showTranscriptInMenuAfterTranscription {
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
                                dictationController.copyTranscriptAgain(transcript)
                            }
                            .font(.caption)
                        }
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
                        Button("Open Microphone Settings") {
                            openMicrophoneSystemSettings()
                        }
                        .font(.caption)
                    }
                }
            }

            if dictationController.shouldShowAccessibilityPrompt {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("To paste directly into the active app, enable Accessibility access for Screamer.")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 10) {
                        Button("Open Accessibility Settings") {
                            openAccessibilitySystemSettings()
                            dictationController.dismissAccessibilityPrompt()
                        }
                        .font(.caption)
                        Button("Dismiss") {
                            dictationController.dismissAccessibilityPrompt()
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
        .frame(width: 240)
        .task {
            modelStore.refreshCatalog()
            await dictationController.checkWorker()
        }
        .onChange(of: dictationController.state) { _, newState in
            switch newState {
            case .success:
                isShowingFullTranscript = false
            default:
                break
            }
        }
    }

    private var recordingButtonLabel: String {
        switch dictationController.state {
        case .recording:
            return "Stop Recording"
        case .transcribing:
            return "Transcribing…"
        default:
            return "Start Recording"
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

    private func displayTranscriptText(for transcript: String) -> String {
        guard transcript.count > 200, !isShowingFullTranscript else {
            return transcript
        }
        return "\(String(transcript.prefix(200)))…"
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
}
