import SwiftUI

@main
struct ScreamerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Screamer", systemImage: "mic.fill") {
            MenuBarView(
                hotkeyDisplayValue: appDelegate.hotkeyDisplayValue,
                dictationController: appDelegate.dictationController,
                modelStore: appDelegate.modelStore
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                onUpdateHotkey: { appDelegate.updateHotkey($0) },
                onLMStudioConfigurationChanged: { appDelegate.refreshLMStudioClientConfiguration() },
                modelStore: appDelegate.modelStore
            )
        }

        Window("History", id: "transcript-history") {
            if let transcriptStore = appDelegate.transcriptStore {
                TranscriptHistoryView(
                    transcriptStore: transcriptStore,
                    modelStore: appDelegate.modelStore
                )
            } else {
                ContentUnavailableView(
                    "History Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Screamer could not open the transcript history database.")
                )
                .frame(minWidth: 760, minHeight: 540)
                .padding()
            }
        }
    }
}
