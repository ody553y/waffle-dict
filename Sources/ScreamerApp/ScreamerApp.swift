import SwiftUI

@main
struct ScreamerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.historySelectionActions) private var historySelectionActions
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra(
            localized(
                "app.menuBar.title",
                default: "Screamer",
                comment: "Menu bar extra title for the Screamer app"
            ),
            systemImage: "mic.fill"
        ) {
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
                modelStore: appDelegate.modelStore,
                updaterSettings: appDelegate.updaterSettings
            )
        }

        Window(
            localized(
                "history.window.title",
                default: "History",
                comment: "Window title for transcript history"
            ),
            id: "transcript-history"
        ) {
            if let transcriptStore = appDelegate.transcriptStore {
                TranscriptHistoryView(
                    transcriptStore: transcriptStore,
                    modelStore: appDelegate.modelStore
                )
            } else {
                ContentUnavailableView(
                    localized(
                        "history.unavailable.title",
                        default: "History Unavailable",
                        comment: "Title shown when transcript history database cannot be opened"
                    ),
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        localized(
                            "history.unavailable.description",
                            default: "Screamer could not open the transcript history database.",
                            comment: "Description shown when transcript history database cannot be opened"
                        )
                    )
                )
                .frame(minWidth: 760, minHeight: 540)
                .padding()
            }
        }
        .commands {
            CommandMenu(
                localized(
                    "history.menu.title",
                    default: "History",
                    comment: "Command menu title for history actions"
                )
            ) {
                Button(
                    localized(
                        "history.menu.openHistory",
                        default: "Open History",
                        comment: "Command menu item for opening transcript history"
                    )
                ) {
                    openWindow(id: "transcript-history")
                }
                .keyboardShortcut("h")

                Divider()

                Button(
                    localized(
                        "history.menu.find",
                        default: "Find",
                        comment: "Command menu item for focusing search"
                    )
                ) {
                    historySelectionActions?.focusSearch()
                }
                .keyboardShortcut("f")
                .disabled(historySelectionActions == nil)

                Button(
                    localized(
                        "history.menu.selectAll",
                        default: "Select All",
                        comment: "Command menu item for selecting all visible transcripts"
                    )
                ) {
                    historySelectionActions?.selectAllVisible()
                }
                .keyboardShortcut("a")
                .disabled(historySelectionActions == nil)

                Button(
                    localized(
                        "history.menu.copyTranscript",
                        default: "Copy Transcript Text",
                        comment: "Command menu item for copying selected transcript text"
                    )
                ) {
                    historySelectionActions?.copySelection()
                }
                .keyboardShortcut("c")
                .disabled(historySelectionActions == nil)

                Button(
                    localized(
                        "history.menu.exportTranscript",
                        default: "Export Transcript",
                        comment: "Command menu item for exporting selected transcript"
                    )
                ) {
                    historySelectionActions?.exportSelection()
                }
                .keyboardShortcut("e")
                .disabled(historySelectionActions == nil)

                Button(
                    localized(
                        "history.menu.deleteTranscript",
                        default: "Delete Transcript",
                        comment: "Command menu item for deleting selected transcript"
                    )
                ) {
                    historySelectionActions?.deleteSelection()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(historySelectionActions == nil)
            }
        }
    }
}
