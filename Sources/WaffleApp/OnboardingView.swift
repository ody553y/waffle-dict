import AppKit
import SwiftUI
import WaffleCore

struct OnboardingView: View {
    let onComplete: () -> Void
    @ObservedObject var modelStore: ModelStore

    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    private let settingsRouter = SettingsTabRouter()
    private let permissionsService = PermissionsService()
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome to Waffle")
                    .font(.largeTitle.bold())

                Text("Complete these setup steps to get to a ready-to-transcribe state.")
                    .foregroundStyle(.secondary)

                GroupBox("Readiness") {
                    VStack(alignment: .leading, spacing: 8) {
                        readinessRow(
                            "Microphone permission granted",
                            isReady: readiness.microphoneGranted
                        )
                        readinessRow(
                            "At least one transcription model installed",
                            isReady: readiness.hasInstalledModel
                        )
                        readinessRow(
                            "Accessibility permission enabled (recommended)",
                            isReady: accessibilityGranted
                        )

                        if readiness.isReadyToTranscribe {
                            Text("You are ready to transcribe.")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text("Complete the missing items below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button("Re-check Status") {
                            refreshStatus()
                        }
                    }
                    .padding(.top, 2)
                }

                GroupBox("1) Microphone Permission") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Allow microphone access in System Settings so Waffle can record audio.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Open Microphone System Settings") {
                            openSystemSettings(.microphone)
                        }
                    }
                    .padding(.top, 2)
                }

                GroupBox("2) Model Installation and Selection") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Open Settings > Models to download and select your transcription model.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Open Models in Settings") {
                            openSettingsTab(.models)
                        }
                    }
                    .padding(.top, 2)
                }

                GroupBox("3) Accessibility + Paste Behavior") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility permission allows reliable paste into other apps. Paste preferences live in Settings > General.")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            Button("Open Accessibility System Settings") {
                                openSystemSettings(.accessibility)
                            }
                            Button("Open General in Settings") {
                                openSettingsTab(.general)
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                GroupBox("4) LM Studio Connection") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Configure LM Studio host, port, and model defaults in Settings > AI.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Open AI in Settings") {
                            openSettingsTab(.ai)
                        }
                    }
                    .padding(.top, 2)
                }

                HStack(spacing: 10) {
                    Button(readiness.isReadyToTranscribe ? "Finish and Open Control Center" : "Mark Setup Complete") {
                        onComplete()
                        if readiness.isReadyToTranscribe {
                            openWindow(id: "control-center")
                        }
                        NSApp.keyWindow?.close()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Skip For Now") {
                        NSApp.keyWindow?.close()
                    }
                }
            }
            .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
            .padding(22)
        }
        .onAppear {
            modelStore.refreshCatalog()
            refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
    }

    private func openSettingsTab(_ tab: SettingsTab) {
        settingsRouter.route(to: tab)
        SettingsOpener.open(openSettings: { openSettings() })
    }

    private func openSystemSettings(_ link: OnboardingSystemSettingsLink) {
        guard let url = link.url else { return }
        NSWorkspace.shared.open(url)
    }

    private var readiness: OnboardingReadiness {
        OnboardingReadiness(
            microphoneGranted: microphoneGranted,
            hasInstalledModel: modelStore.hasInstalledModels
        )
    }

    private func refreshStatus() {
        microphoneGranted = permissionsService.microphoneStatus == .granted
        accessibilityGranted = permissionsService.isAccessibilityGranted
    }

    @ViewBuilder
    private func readinessRow(_ text: String, isReady: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isReady ? Color.green : Color.secondary)
            Text(text)
        }
        .font(.subheadline)
    }
}
