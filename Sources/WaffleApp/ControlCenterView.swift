import SwiftUI
import WaffleCore

struct ControlCenterView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    @ObservedObject var dictationController: DictationController
    @ObservedObject var modelStore: ModelStore
    let transcriptStore: TranscriptStore?

    @State private var recentRecords: [TranscriptRecord] = []
    @State private var isLoadingRecent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusCard
                quickActionsCard
                recentTranscriptsCard
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 420)
        .task {
            modelStore.refreshCatalog()
            await dictationController.checkWorker()
            await loadRecentTranscripts()
        }
    }

    private var statusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text("Worker: \(dictationController.workerStatus)")
                        .font(.headline)
                }

                Text("Recording: \(recordingStatusText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(
                    "Model: \(modelStore.selectedEntry?.displayName ?? "No installed model selected")"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quickActionsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quick Actions")
                    .font(.headline)

                HStack(spacing: 10) {
                    Button(recordButtonTitle) {
                        Task {
                            await dictationController.handleRecordButtonTap()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        dictationController.isTranscribing
                            || (modelStore.hasInstalledModels == false && dictationController.isRecording == false)
                    )

                    Button("Open Settings") {
                        SettingsOpener.open(openSettings: { openSettings() })
                    }
                    .buttonStyle(.bordered)

                    Button("Open History") {
                        openWindow(id: "transcript-history")
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    Button("Open Review") {
                        NotificationCenter.default.post(name: .waffleOpenReviewQueue, object: nil)
                    }
                    .buttonStyle(.bordered)

                    Button("Import File") {
                        openWindow(id: "transcript-history")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            NotificationCenter.default.post(name: .waffleImportAudioFiles, object: nil)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recentTranscriptsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent Transcripts")
                        .font(.headline)
                    Spacer()
                    if isLoadingRecent {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Refresh") {
                        Task {
                            await loadRecentTranscripts()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingRecent)
                }

                if recentRecords.isEmpty {
                    Text("No transcripts yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recentRecords) { record in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(record.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                        .font(.subheadline)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Button("Open") {
                                    openInHistory(recordID: record.id)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusColor: Color {
        switch dictationController.workerStatus.lowercased() {
        case "ok", "model loading…", "model loading...":
            return .green
        case "offline":
            return .red
        default:
            return .yellow
        }
    }

    private var recordingStatusText: String {
        if dictationController.isRecording {
            return "Recording"
        }
        if dictationController.isTranscribing {
            return "Transcribing"
        }
        return "Idle"
    }

    private var recordButtonTitle: String {
        dictationController.isRecording ? "Stop Recording" : "Start Recording"
    }

    private func openInHistory(recordID: Int64?) {
        guard let recordID else { return }
        openWindow(id: "transcript-history")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(
                name: .waffleSelectTranscriptInHistory,
                object: nil,
                userInfo: ["transcriptID": recordID]
            )
        }
    }

    private func loadRecentTranscripts() async {
        guard let transcriptStore else {
            recentRecords = []
            return
        }

        isLoadingRecent = true
        let loaded = await Task.detached(priority: .utility) {
            (try? transcriptStore.fetchAll(limit: 8)) ?? []
        }.value
        recentRecords = loaded
        isLoadingRecent = false
    }
}
