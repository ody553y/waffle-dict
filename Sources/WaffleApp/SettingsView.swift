import AppKit
import Carbon.HIToolbox
import SwiftUI
import WaffleCore

struct SettingsView: View {
    let onUpdateHotkey: (GlobalHotkey) -> Void
    let onLMStudioConfigurationChanged: () -> Void
    let transcriptStore: TranscriptStore?
    @ObservedObject var modelStore: ModelStore
    @ObservedObject var updaterSettings: UpdaterSettings

    var body: some View {
        TabView {
            GeneralSettingsView(modelStore: modelStore, updaterSettings: updaterSettings)
                .tabItem {
                    Label(
                        localized(
                            "settings.tab.general",
                            default: "General",
                            comment: "Settings tab title for general preferences"
                        ),
                        systemImage: "gear"
                    )
                }
            ModelsSettingsView(modelStore: modelStore)
                .tabItem {
                    Label(
                        localized(
                            "settings.tab.models",
                            default: "Models",
                            comment: "Settings tab title for model downloads and management"
                        ),
                        systemImage: "arrow.down.circle"
                    )
                }
            AISettingsView(
                onConfigurationChanged: onLMStudioConfigurationChanged,
                transcriptStore: transcriptStore
            )
                .tabItem {
                    Label(
                        localized(
                            "settings.tab.ai",
                            default: "AI",
                            comment: "Settings tab title for LM Studio AI configuration"
                        ),
                        systemImage: "sparkles"
                    )
                }
            Group {
                if let transcriptStore {
                    StatisticsSettingsView(store: transcriptStore, modelStore: modelStore)
                } else {
                    ContentUnavailableView(
                        localized(
                            "settings.statistics.unavailable.title",
                            default: "Statistics unavailable",
                            comment: "Title shown when transcript store is unavailable in settings context"
                        ),
                        systemImage: "chart.bar",
                        description: Text(
                            localized(
                                "settings.statistics.unavailable.description",
                                default: "Open the app normally to view usage statistics.",
                                comment: "Description shown when statistics cannot be loaded in settings context"
                            )
                        )
                    )
                }
            }
            .tabItem {
                Label(
                    localized(
                        "settings.tab.statistics",
                        default: "Statistics",
                        comment: "Settings tab title for transcript usage statistics"
                    ),
                    systemImage: "chart.bar"
                )
            }
            KeyboardSettingsView(onUpdateHotkey: onUpdateHotkey)
                .tabItem {
                    Label(
                        localized(
                            "settings.tab.keyboard",
                            default: "Keyboard",
                            comment: "Settings tab title for keyboard shortcut configuration"
                        ),
                        systemImage: "keyboard"
                    )
                }
        }
        .frame(width: 540, height: 360)
    }
}

struct GeneralSettingsView: View {
    @Environment(\.openWindow) private var openWindow

    @AppStorage("pasteIntoActiveApp") private var pasteIntoActiveApp = true
    @AppStorage("copyToClipboardAsFallback") private var copyToClipboardAsFallback = true
    @AppStorage("showPreviewAfterDictation")
    private var showPreviewAfterDictation = true
    @AppStorage("previewAutoDismissSeconds")
    private var previewAutoDismissSeconds = 10
    @AppStorage("languageHint")
    private var languageHint = ""
    @AppStorage("retainAudioRecordings")
    private var retainAudioRecordings = false
    @AppStorage("iCloudBackupEnabled")
    private var iCloudBackupEnabled = false

    @ObservedObject var modelStore: ModelStore
    @ObservedObject var updaterSettings: UpdaterSettings
    private let debugInfoDefaultsKey = "showDebugInfo"
    private let backupService = iCloudBackupService()
    @State private var isICloudAvailable: Bool?
    @State private var isICloudBackupsSheetPresented = false

    var body: some View {
        Form {
            Toggle(
                localized(
                    "settings.general.pasteIntoActiveApp",
                    default: "Paste into active app after transcription",
                    comment: "Toggle label for auto-paste behavior after dictation"
                ),
                isOn: $pasteIntoActiveApp
            )
            Toggle(
                localized(
                    "settings.general.copyFallback",
                    default: "Copy to clipboard as fallback",
                    comment: "Toggle label for clipboard fallback when paste cannot run"
                ),
                isOn: $copyToClipboardAsFallback
            )
            Toggle(
                localized(
                    "settings.general.showPreviewAfterDictation",
                    default: "Show preview after dictation",
                    comment: "Toggle label for showing menu bar transcript preview after dictation"
                ),
                isOn: $showPreviewAfterDictation
            )

            Stepper(
                value: $previewAutoDismissSeconds,
                in: 0 ... 30,
                step: 1
            ) {
                Text(
                    localizedFormat(
                        "settings.general.previewAutoDismissSeconds",
                        default: "Preview auto-dismiss (seconds): %d",
                        comment: "Stepper label controlling transcript preview auto-dismiss seconds",
                        previewAutoDismissSeconds
                    )
                )
            }
            .disabled(showPreviewAfterDictation == false)

            Text(
                localized(
                    "settings.general.previewAutoDismissHint",
                    default: "Set to 0 to keep the preview visible until dismissed.",
                    comment: "Help text for preview auto-dismiss stepper"
                )
            )
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle(
                localized(
                    "settings.general.retainAudioRecordings",
                    default: "Retain audio recordings",
                    comment: "Toggle label for retaining WAV recordings linked to transcripts"
                ),
                isOn: $retainAudioRecordings
            )

            Text(
                localized(
                    "settings.general.retainAudioRecordings.note",
                    default: "WAV files use ~1.9 MB/minute. Audio is not included in transcript exports.",
                    comment: "Help text warning about retained audio file size and export behavior"
                )
            )
                .font(.caption2)
                .foregroundStyle(.secondary)

            Section(
                localized(
                    "settings.general.iCloudBackup.section",
                    default: "iCloud Backup",
                    comment: "Section title for iCloud transcript backup preferences"
                )
            ) {
                Toggle(
                    localized(
                        "settings.general.iCloudBackup.enabled",
                        default: "Back up transcripts to iCloud Drive",
                        comment: "Toggle label for enabling iCloud transcript backups"
                    ),
                    isOn: $iCloudBackupEnabled
                )

                Text(
                    localized(
                        "settings.general.iCloudBackup.note",
                        default: "Transcripts are saved as .waffle files in iCloud Drive > Waffle > Transcripts.",
                        comment: "Help text describing where iCloud backup files are stored"
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                if isICloudAvailable == false {
                    Text(
                        localized(
                            "settings.general.iCloudBackup.unavailable",
                            default: "iCloud Drive is not available. Sign in to iCloud in System Settings.",
                            comment: "Message shown when iCloud Drive container access is unavailable"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button(
                        localized(
                            "settings.general.iCloudBackup.browse",
                            default: "Browse iCloud Backups…",
                            comment: "Button title for opening the iCloud backups browser sheet"
                        )
                    ) {
                        isICloudBackupsSheetPresented = true
                    }
                    .disabled(isICloudAvailable != true)

                    Button(
                        localized(
                            "settings.general.iCloudBackup.refreshAvailability",
                            default: "Refresh Availability",
                            comment: "Button title for re-checking iCloud container availability"
                        )
                    ) {
                        Task {
                            await refreshICloudAvailability()
                        }
                    }

                    if isICloudAvailable == nil {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section(
                localized(
                    "settings.general.transcriptionModel.section",
                    default: "Transcription Model",
                    comment: "Section title for selecting the transcription model"
                )
            ) {
                if modelStore.installedEntries.isEmpty {
                    Text(
                        localized(
                            "settings.general.transcriptionModel.empty",
                            default: "No installed models yet. Open the Models tab to download one.",
                            comment: "Message shown when no transcription models are installed"
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        localized(
                            "settings.general.transcriptionModel.picker",
                            default: "Transcription Model",
                            comment: "Picker label for selecting installed transcription model"
                        ),
                        selection: Binding(
                            get: { modelStore.resolvedSelectedModelID ?? "" },
                            set: { modelStore.setSelectedModelID($0) }
                        )
                    ) {
                        ForEach(modelStore.installedEntries) { entry in
                            Text(entry.displayName).tag(entry.id)
                        }
                    }
                    Text(
                        localized(
                            "settings.general.transcriptionModel.hint",
                            default: "The next transcription will use the selected installed model.",
                            comment: "Help text below transcription model picker"
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(
                localized(
                    "settings.general.languageHint.section",
                    default: "Language Hint",
                    comment: "Section title for dictation language hint settings"
                )
            ) {
                Picker(
                    localized(
                        "settings.general.languageHint.picker",
                        default: "Language",
                        comment: "Picker label for selecting language hint"
                    ),
                    selection: $languageHint
                ) {
                    Text(
                        localized(
                            "settings.general.languageHint.autoDetect",
                            default: "Auto-detect",
                            comment: "Option label for automatic language detection"
                        )
                    ).tag("")
                    ForEach(AppLanguageOption.all) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .disabled(isParakeetSelected)

                if isParakeetSelected {
                    Text(
                        localized(
                            "settings.general.languageHint.parakeetOnly",
                            default: "Parakeet supports English only. Waffle will send \"en\" while Parakeet is selected.",
                            comment: "Help text when Parakeet model is selected and language hint is locked to English"
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        localized(
                            "settings.general.languageHint.help",
                            default: "Auto-detect sends no language hint. Selecting a language sends its ISO 639-1 code.",
                            comment: "Help text explaining language hint behavior"
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(
                localized(
                    "settings.general.shortcuts.section",
                    default: "Keyboard Shortcuts",
                    comment: "Section title listing keyboard shortcuts"
                )
            ) {
                LabeledContent(
                    localized(
                        "settings.general.shortcuts.recordStop",
                        default: "Record / Stop",
                        comment: "Shortcut row label for record/stop action"
                    )
                ) {
                    Text(
                        localized(
                            "settings.general.shortcuts.globalHotkey",
                            default: "Global hotkey",
                            comment: "Displayed shortcut value for global record hotkey"
                        )
                    )
                }
                LabeledContent(
                    localized(
                        "settings.general.shortcuts.openHistory",
                        default: "Open History",
                        comment: "Shortcut row label for opening transcript history"
                    )
                ) {
                    Text("\u{2318}H")
                }
                LabeledContent(
                    localized(
                        "settings.general.shortcuts.openSettings",
                        default: "Open Settings",
                        comment: "Shortcut row label for opening settings"
                    )
                ) {
                    Text("\u{2318},")
                }
                LabeledContent(
                    localized(
                        "settings.general.shortcuts.find",
                        default: "Find",
                        comment: "Shortcut row label for find action in history"
                    )
                ) {
                    Text("\u{2318}F")
                }
                LabeledContent(
                    localized(
                        "settings.general.shortcuts.copyTranscript",
                        default: "Copy Transcript",
                        comment: "Shortcut row label for copying transcript text"
                    )
                ) {
                    Text("\u{2318}C")
                }
                LabeledContent(
                    localized(
                        "settings.general.shortcuts.export",
                        default: "Export",
                        comment: "Shortcut row label for exporting transcripts"
                    )
                ) {
                    Text("\u{2318}E")
                }
                LabeledContent(
                    localized(
                        "settings.general.shortcuts.deleteSelected",
                        default: "Delete Selected",
                        comment: "Shortcut row label for deleting selected transcripts"
                    )
                ) {
                    Text("\u{2318}\u{232b}")
                }
                LabeledContent(
                    localized(
                        "settings.general.shortcuts.selectAllVisible",
                        default: "Select All Visible",
                        comment: "Shortcut row label for selecting all visible transcript rows"
                    )
                ) {
                    Text("\u{2318}A")
                }
                LabeledContent(
                    localized(
                        "settings.general.shortcuts.listNavigation",
                        default: "List Navigation",
                        comment: "Shortcut row label for keyboard list navigation keys"
                    )
                ) {
                    Text("\u{2191} / \u{2193}, Return, Esc")
                }
            }

            if shouldShowDebugSection {
                Section(
                    localized(
                        "settings.general.debug.section",
                        default: "Debug",
                        comment: "Section title for performance debug metrics"
                    )
                ) {
                    LabeledContent(
                        localized(
                            "settings.general.debug.startup",
                            default: "Startup",
                            comment: "Debug metric row label for app startup timing"
                        )
                    ) {
                        Text(metricValue(for: "app.startup"))
                    }

                    LabeledContent(
                        localized(
                            "settings.general.debug.transcriptionAvg",
                            default: "Transcription Avg",
                            comment: "Debug metric row label for average transcription timing"
                        )
                    ) {
                        Text(combinedMetricValue(for: ["dictation.transcription.e2e", "file.transcription.e2e"]))
                    }

                    LabeledContent(
                        localized(
                            "settings.general.debug.workerHealth",
                            default: "Worker Health",
                            comment: "Debug metric row label for worker health check timing"
                        )
                    ) {
                        Text(metricValue(for: "worker.health.check"))
                    }

                    LabeledContent(
                        localized(
                            "settings.general.debug.dbSave",
                            default: "DB Save",
                            comment: "Debug metric row label for database save timing"
                        )
                    ) {
                        Text(metricValue(for: "db.save"))
                    }

                    LabeledContent(
                        localized(
                            "settings.general.debug.dbFetchAll",
                            default: "DB Fetch All",
                            comment: "Debug metric row label for database fetch-all timing"
                        )
                    ) {
                        Text(metricValue(for: "db.fetchAll"))
                    }

                    LabeledContent(
                        localized(
                            "settings.general.debug.dbSearch",
                            default: "DB Search",
                            comment: "Debug metric row label for database search timing"
                        )
                    ) {
                        Text(metricValue(for: "db.search"))
                    }

                    Button(
                        localized(
                            "settings.general.debug.copyReport",
                            default: "Copy Report",
                            comment: "Action title to copy performance report to clipboard"
                        )
                    ) {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(PerformanceMetrics.shared.report(), forType: .string)
                    }

                    Text(
                        localized(
                            "settings.general.debug.enableHint",
                            default: "Enable with terminal: defaults write com.waffle.app showDebugInfo -bool true",
                            comment: "Hint explaining how to enable debug section through defaults"
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section(
                localized(
                    "settings.general.updates.section",
                    default: "Updates",
                    comment: "Section title for app update preferences"
                )
            ) {
                Toggle(
                    localized(
                        "settings.general.updates.autoCheck",
                        default: "Check for updates automatically",
                        comment: "Toggle label controlling automatic update checks"
                    ),
                    isOn: Binding(
                        get: { updaterSettings.automaticallyChecksForUpdates },
                        set: { updaterSettings.setAutomaticallyChecksForUpdates($0) }
                    )
                )
                .disabled(updaterSettings.isUpdaterReady == false)

                HStack {
                    Text(
                        localized(
                            "settings.general.updates.currentVersion",
                            default: "Current Version",
                            comment: "Label for currently installed app version"
                        )
                    )
                    Spacer()
                    Text(updaterSettings.currentVersion)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(
                        localized(
                            "settings.general.updates.lastCheck",
                            default: "Last Check",
                            comment: "Label for last time update check was run"
                        )
                    )
                    Spacer()
                    Text(updaterSettings.lastUpdateCheckDescription)
                        .foregroundStyle(.secondary)
                }

                Button(
                    localized(
                        "settings.general.updates.checkNow",
                        default: "Check Now",
                        comment: "Action title to manually check for updates"
                    )
                ) {
                    updaterSettings.checkForUpdates()
                }
                .disabled(updaterSettings.isUpdaterReady == false)
            }
        }
        .padding()
        .task {
            modelStore.refreshCatalog()
            updaterSettings.refresh()
            await refreshICloudAvailability()
        }
        .sheet(isPresented: $isICloudBackupsSheetPresented) {
            ICloudBackupsBrowserSheet(
                backupService: backupService,
                onRestoreBackup: { backupURL in
                    restoreBackup(backupURL)
                }
            )
        }
    }

    private var isParakeetSelected: Bool {
        modelStore.selectedEntry?.family == .parakeet
    }

    private var shouldShowDebugSection: Bool {
        UserDefaults.standard.bool(forKey: debugInfoDefaultsKey)
    }

    private func metricValue(for label: String) -> String {
        guard let summary = PerformanceMetrics.shared.summary(for: label) else {
            return localized(
                "settings.general.debug.noSamples",
                default: "No samples",
                comment: "Fallback text when no performance metric samples are available"
            )
        }
        return localizedFormat(
            "settings.general.debug.metricValue",
            default: "%@ avg (%dx)",
            comment: "Formatted debug metric value showing average duration and sample count",
            formatMilliseconds(summary.meanDurationSeconds),
            summary.sampleCount
        )
    }

    private func combinedMetricValue(for labels: [String]) -> String {
        let summaries = labels.compactMap { PerformanceMetrics.shared.summary(for: $0) }
        guard summaries.isEmpty == false else {
            return localized(
                "settings.general.debug.noSamples",
                default: "No samples",
                comment: "Fallback text when no performance metric samples are available"
            )
        }

        let sampleCount = summaries.reduce(0) { $0 + $1.sampleCount }
        guard sampleCount > 0 else {
            return localized(
                "settings.general.debug.noSamples",
                default: "No samples",
                comment: "Fallback text when no performance metric samples are available"
            )
        }

        let totalDurationSeconds = summaries.reduce(0.0) { $0 + $1.totalDurationSeconds }
        let meanDurationSeconds = totalDurationSeconds / Double(sampleCount)
        return localizedFormat(
            "settings.general.debug.metricValue.combined",
            default: "%@ avg (%dx)",
            comment: "Formatted debug metric value showing average duration and sample count",
            formatMilliseconds(meanDurationSeconds),
            sampleCount
        )
    }

    private func formatMilliseconds(_ durationSeconds: Double) -> String {
        String(format: "%.1fms", durationSeconds * 1_000)
    }

    private func refreshICloudAvailability() async {
        let availability = await Task.detached(priority: .utility) { [backupService] in
            backupService.isAvailable
        }.value

        isICloudAvailable = availability
    }

    private func restoreBackup(_ backupURL: URL) {
        openWindow(id: "transcript-history")

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            NotificationCenter.default.post(
                name: .waffleImportTranscriptArchive,
                object: nil,
                userInfo: TranscriptArchiveImportNotification.userInfo(for: [backupURL])
            )
        }
    }
}

private struct ICloudBackupsBrowserSheet: View {
    let backupService: iCloudBackupService
    let onRestoreBackup: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var backups: [BackupEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pendingDeleteBackupURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(
                    localized(
                        "settings.general.iCloudBackup.browser.title",
                        default: "iCloud Backups",
                        comment: "Title for iCloud backups browser sheet"
                    )
                )
                .font(.headline)

                Spacer()

                Button(
                    localized(
                        "settings.general.iCloudBackup.browser.openFinder",
                        default: "Open in Finder",
                        comment: "Button title for revealing iCloud backups directory in Finder"
                    )
                ) {
                    revealBackupsDirectoryInFinder()
                }

                Button(
                    localized(
                        "settings.models.refresh",
                        default: "Refresh",
                        comment: "Action title to refresh model catalog in settings"
                    )
                ) {
                    Task {
                        await loadBackups()
                    }
                }
                .disabled(isLoading)
            }

            if isLoading && backups.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if backups.isEmpty {
                Text(
                    localized(
                        "settings.general.iCloudBackup.browser.empty",
                        default: "No backups found.",
                        comment: "Empty-state message shown when there are no iCloud backup files"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                List(backups) { backup in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(backup.url.lastPathComponent)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(backupMetadataText(for: backup))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Button(
                                localized(
                                    "settings.general.iCloudBackup.browser.restore",
                                    default: "Restore",
                                    comment: "Button title for restoring an iCloud backup archive"
                                )
                            ) {
                                onRestoreBackup(backup.url)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)

                            Button(
                                localized(
                                    "action.delete",
                                    default: "Delete",
                                    comment: "Action title for deleting selected transcripts"
                                ),
                                role: .destructive
                            ) {
                                pendingDeleteBackupURL = backup.url
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(
                    localized(
                        "action.close",
                        default: "Close",
                        comment: "Action title for closing a sheet"
                    )
                ) {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 420)
        .task {
            await loadBackups()
        }
        .alert(
            pendingDeleteBackupURL?.lastPathComponent
                ?? localized(
                    "settings.general.iCloudBackup.browser.delete.titleFallback",
                    default: "Delete backup?",
                    comment: "Fallback title for delete-backup confirmation alert"
                ),
            isPresented: Binding(
                get: { pendingDeleteBackupURL != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingDeleteBackupURL = nil
                    }
                }
            )
        ) {
            Button(
                localized(
                    "action.delete",
                    default: "Delete",
                    comment: "Action title for deleting selected transcripts"
                ),
                role: .destructive
            ) {
                deletePendingBackup()
            }
            Button(
                localized(
                    "action.cancel",
                    default: "Cancel",
                    comment: "Generic action title for canceling a dialog"
                ),
                role: .cancel
            ) {
                pendingDeleteBackupURL = nil
            }
        } message: {
            if let pendingDeleteBackupURL {
                Text(
                    localizedFormat(
                        "settings.general.iCloudBackup.browser.delete.message",
                        default: "Delete \"%@\" from iCloud Drive? This does not delete local transcripts.",
                        comment: "Confirmation message shown before deleting an iCloud backup file",
                        pendingDeleteBackupURL.lastPathComponent
                    )
                )
            }
        }
    }

    private func loadBackups() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let urls = try await Task.detached(priority: .utility) { [backupService] in
                try backupService.listBackups()
            }.value
            backups = urls.map { url in
                let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return BackupEntry(
                    url: url,
                    fileSizeBytes: resourceValues?.fileSize.map { Int64($0) },
                    modifiedAt: resourceValues?.contentModificationDate
                )
            }
            errorMessage = nil
        } catch {
            backups = []
            errorMessage = localizedFormat(
                "settings.general.iCloudBackup.browser.loadFailed",
                default: "Failed to load iCloud backups: %@",
                comment: "Error shown when iCloud backup list loading fails",
                error.localizedDescription
            )
        }
    }

    private func deletePendingBackup() {
        guard let pendingDeleteBackupURL else { return }
        self.pendingDeleteBackupURL = nil

        Task {
            do {
                try await Task.detached(priority: .utility) { [backupService] in
                    try backupService.deleteBackup(at: pendingDeleteBackupURL)
                }.value
                await loadBackups()
            } catch {
                errorMessage = localizedFormat(
                    "settings.general.iCloudBackup.browser.deleteFailed",
                    default: "Failed to delete backup: %@",
                    comment: "Error shown when deleting an iCloud backup file fails",
                    error.localizedDescription
                )
            }
        }
    }

    private func revealBackupsDirectoryInFinder() {
        Task {
            let containerURL = await Task.detached(priority: .utility) { [backupService] in
                backupService.containerURL
            }.value
            guard let containerURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([containerURL])
        }
    }

    private func backupMetadataText(for backup: BackupEntry) -> String {
        let fileSizeText: String
        if let fileSizeBytes = backup.fileSizeBytes {
            fileSizeText = ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
        } else {
            fileSizeText = localized(
                "settings.general.iCloudBackup.browser.sizeUnknown",
                default: "Unknown size",
                comment: "Fallback text for iCloud backup files without known size metadata"
            )
        }

        let dateText: String
        if let modifiedAt = backup.modifiedAt {
            dateText = modifiedAt.formatted(date: .abbreviated, time: .shortened)
        } else {
            dateText = localized(
                "settings.general.iCloudBackup.browser.dateUnknown",
                default: "Unknown date",
                comment: "Fallback text for iCloud backup files without known date metadata"
            )
        }

        return "\(fileSizeText) • \(dateText)"
    }

    private struct BackupEntry: Identifiable {
        let url: URL
        let fileSizeBytes: Int64?
        let modifiedAt: Date?

        var id: URL { url }
    }
}

struct ModelsSettingsView: View {
    @ObservedObject var modelStore: ModelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(
                    localized(
                        "settings.models.refresh",
                        default: "Refresh",
                        comment: "Action title to refresh model catalog in settings"
                    )
                ) {
                    modelStore.refreshCatalogFromRemote()
                }
                .buttonStyle(.bordered)

                if let remoteUpdateNotice = modelStore.remoteUpdateNotice {
                    Text(remoteUpdateNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            List(modelStore.catalog) { entry in
                ModelRowView(entry: entry, modelStore: modelStore)
            }
        }
        .padding(.horizontal)
        .task {
            modelStore.refreshCatalog()
        }
    }
}

struct AISettingsView: View {
    private static let defaultAutoSummarizePrompt =
        "Summarize this transcript in 3–5 bullet points, focusing on key decisions and action items."

    @AppStorage("lmStudioHost") private var lmStudioHost = "127.0.0.1"
    @AppStorage("lmStudioPort") private var lmStudioPort = "1234"
    @AppStorage("lmStudioModelID") private var lmStudioModelID = ""
    @AppStorage("lmStudioStreaming") private var lmStudioStreaming = true
    @AppStorage("lmStudioDefaultTranslationLanguage")
    private var lmStudioDefaultTranslationLanguage = AppLanguageOption.defaultCode
    @AppStorage("autoSummarizeEnabled") private var autoSummarizeEnabled = false
    @AppStorage("autoSummarizePrompt") private var autoSummarizePrompt = Self.defaultAutoSummarizePrompt

    let onConfigurationChanged: () -> Void
    let transcriptStore: TranscriptStore?

    @State private var promptTemplates: [PromptTemplate] = []
    @State private var exportPipelines: [ExportPipeline] = []
    @State private var availableModels: [LMStudioModel] = []
    @State private var isConnected = false
    @State private var connectionMessage = localized(
        "settings.ai.connection.notConnected",
        default: "Not connected",
        comment: "Default LM Studio connection status text"
    )
    @State private var isTestingConnection = false
    @State private var isAddTemplateSheetPresented = false
    @State private var pipelineEditorState: PipelineEditorState?
    @State private var newTemplateName = ""
    @State private var newTemplatePrompt = ""
    @State private var pendingDeleteTemplate: PromptTemplate?
    @State private var pendingDeletePipeline: ExportPipeline?
    @State private var templateErrorMessage: String?
    @State private var pipelineErrorMessage: String?
    @State private var hasTranscriptsForPipelineRun = false
    @State private var runningPipelineIDs: Set<UUID> = []
    @State private var pipelineRunFeedbackByID: [UUID: PipelineRunFeedback] = [:]
    @State private var webhookConfiguration = WebhookConfiguration.load()
    @State private var webhookURLValidationMessage: String?
    @State private var webhookTestMessage: String?
    @State private var webhookTestMessageIsError = false
    @State private var isSendingWebhookTest = false
    @State private var webhookDeliveryEntries: [WebhookDeliveryEntry] = []
    private let promptTemplateStore = PromptTemplateStore()
    private let exportPipelineStore = ExportPipelineStore()
    private let webhookDeliveryLog = WebhookDeliveryLog()
    private let webhookService = WebhookService()

    var body: some View {
        Form {
            Section(
                localized(
                    "settings.ai.connection.section",
                    default: "LM Studio Connection",
                    comment: "Section title for LM Studio connection settings"
                )
            ) {
                TextField(
                    localized(
                        "settings.ai.connection.host",
                        default: "Host",
                        comment: "Text field placeholder for LM Studio host"
                    ),
                    text: $lmStudioHost
                )
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: lmStudioHost) { _, _ in
                        onConfigurationChanged()
                    }

                TextField(
                    localized(
                        "settings.ai.connection.port",
                        default: "Port",
                        comment: "Text field placeholder for LM Studio port"
                    ),
                    text: $lmStudioPort
                )
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: lmStudioPort) { _, _ in
                        onConfigurationChanged()
                    }

                HStack(spacing: 8) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(
                        isConnected
                            ? localized(
                                "settings.ai.connection.connected",
                                default: "Connected",
                                comment: "Connection status when LM Studio is reachable"
                            )
                            : localized(
                                "settings.ai.connection.notConnected",
                                default: "Not connected",
                                comment: "Connection status when LM Studio is unreachable"
                            )
                    )
                        .font(.caption)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    isConnected
                        ? localized(
                            "settings.ai.connection.accessibility.connected",
                            default: "LM Studio connected",
                            comment: "Accessibility label for connected LM Studio status indicator"
                        )
                        : localized(
                            "settings.ai.connection.accessibility.notConnected",
                            default: "LM Studio not connected",
                            comment: "Accessibility label for disconnected LM Studio status indicator"
                        )
                )

                if connectionMessage.isEmpty == false {
                    Text(connectionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(
                    localized(
                        "settings.ai.connection.test",
                        default: "Test Connection",
                        comment: "Action title to test LM Studio connection"
                    )
                ) {
                    Task {
                        await refreshModels()
                    }
                }
                .disabled(isTestingConnection)
                .accessibilityHint(
                    localized(
                        "settings.ai.connection.test.hint",
                        default: "Tests connection to LM Studio",
                        comment: "Accessibility hint for LM Studio test-connection button"
                    )
                )
            }

            Section(
                localized(
                    "settings.ai.defaultModel.section",
                    default: "Default Model",
                    comment: "Section title for default LM Studio model selection"
                )
            ) {
                Picker(
                    localized(
                        "settings.ai.defaultModel.picker",
                        default: "Model",
                        comment: "Picker label for default LM Studio model"
                    ),
                    selection: $lmStudioModelID
                ) {
                    if availableModels.isEmpty {
                        Text(
                            localized(
                                "settings.ai.defaultModel.noneLoaded",
                                default: "No models loaded",
                                comment: "Placeholder option shown when LM Studio has no loaded models"
                            )
                        ).tag("")
                    } else {
                        ForEach(availableModels, id: \.id) { model in
                            Text(model.id).tag(model.id)
                        }
                    }
                }
                .disabled(availableModels.isEmpty)

                Button(
                    localized(
                        "settings.models.refresh",
                        default: "Refresh",
                        comment: "Action title to refresh model catalog in settings"
                    )
                ) {
                    Task {
                        await refreshModels()
                    }
                }
                .disabled(isTestingConnection)

                Text(
                    localized(
                        "settings.ai.defaultModel.help",
                        default: "Models are managed in LM Studio. Load a model there to use it here.",
                        comment: "Help text below default model picker"
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(
                localized(
                    "settings.ai.defaults.section",
                    default: "Defaults",
                    comment: "Section title for AI default preferences"
                )
            ) {
                Toggle(
                    localized(
                        "settings.ai.defaults.streaming",
                        default: "Use streaming responses",
                        comment: "Toggle label for using streaming LM Studio responses"
                    ),
                    isOn: $lmStudioStreaming
                )

                Picker(
                    localized(
                        "settings.ai.defaults.translationLanguage",
                        default: "Default translation language",
                        comment: "Picker label for default translation target language"
                    ),
                    selection: $lmStudioDefaultTranslationLanguage
                ) {
                    ForEach(AppLanguageOption.all) { option in
                        Text(option.name).tag(option.code)
                    }
                }

                Text(
                    localized(
                        "settings.ai.defaults.diarizationHint",
                        default: "Speaker identification requires a HuggingFace token configured in the worker.",
                        comment: "Help text for diarization prerequisites"
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(
                localized(
                    "settings.ai.autoSummarize.section",
                    default: "Auto-Summarization",
                    comment: "Section title for automatic transcript summarization settings"
                )
            ) {
                Toggle(
                    localized(
                        "settings.ai.autoSummarize.enabled",
                        default: "Auto-summarize after transcription",
                        comment: "Toggle label for running automatic summary after dictation"
                    ),
                    isOn: $autoSummarizeEnabled
                )

                Menu(
                    localized(
                        "settings.ai.autoSummarize.useTemplate",
                        default: "Use template…",
                        comment: "Menu button title for selecting auto-summarize prompt template"
                    )
                ) {
                    if promptTemplates.isEmpty {
                        Text(
                            localized(
                                "settings.ai.promptTemplates.empty.short",
                                default: "No templates saved",
                                comment: "Short empty-state text shown in template picker menus"
                            )
                        )
                        .disabled(true)
                    } else {
                        ForEach(promptTemplates) { template in
                            Button(template.name) {
                                autoSummarizePrompt = template.prompt
                            }
                        }
                    }
                }

                TextEditor(text: $autoSummarizePrompt)
                    .frame(minHeight: 96, maxHeight: 180)
                    .font(.body)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                Text(
                    localized(
                        "settings.ai.autoSummarize.note",
                        default: "Requires LM Studio to be running with a model loaded.",
                        comment: "Help text for auto-summarize settings dependency"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(
                localized(
                    "settings.ai.promptTemplates.section",
                    default: "Prompt Templates",
                    comment: "Section title for prompt template management"
                )
            ) {
                HStack(spacing: 8) {
                    Button(
                        localized(
                            "settings.ai.promptTemplates.add",
                            default: "Add Template",
                            comment: "Button title for adding a new prompt template"
                        )
                    ) {
                        beginAddTemplateFlow()
                    }
                    .buttonStyle(.bordered)
                    Spacer()

                    Text(
                        localizedFormat(
                            "settings.ai.promptTemplates.count",
                            default: "%d / %d",
                            comment: "Template count indicator showing current and maximum template count",
                            promptTemplates.count,
                            PromptTemplateStore.maxTemplateCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if promptTemplates.isEmpty {
                    Text(
                        localized(
                            "settings.ai.promptTemplates.empty",
                            default: "No prompt templates yet. Add one to reuse your best prompts.",
                            comment: "Empty-state message shown when there are no prompt templates"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(promptTemplates) { template in
                            PromptTemplateInlineRow(
                                template: template,
                                onUpdate: { updated in
                                    updatePromptTemplate(updated)
                                },
                                onRequestDelete: { selected in
                                    pendingDeleteTemplate = selected
                                },
                                onValidationError: { message in
                                    templateErrorMessage = message
                                }
                            )
                        }
                        .onMove(perform: movePromptTemplates)
                    }
                    .frame(minHeight: 170, maxHeight: 260)
                }

                if let templateErrorMessage {
                    Text(templateErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section(
                localized(
                    "settings.ai.pipelines.section",
                    default: "Pipelines",
                    comment: "Section title for export pipeline configuration"
                )
            ) {
                HStack(spacing: 8) {
                    if exportPipelines.count < ExportPipelineStore.maxPipelineCount {
                        Button(
                            localized(
                                "settings.ai.pipelines.add",
                                default: "Add Pipeline",
                                comment: "Button title for creating a new export pipeline"
                            )
                        ) {
                            beginAddPipelineFlow()
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    Text(
                        localizedFormat(
                            "settings.ai.pipelines.count",
                            default: "%d / %d",
                            comment: "Pipeline count indicator showing current and maximum pipeline count",
                            exportPipelines.count,
                            ExportPipelineStore.maxPipelineCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if exportPipelines.isEmpty {
                    Text(
                        localized(
                            "settings.ai.pipelines.empty",
                            default: "No pipelines yet. Add one to chain prompt templates after transcription.",
                            comment: "Empty-state message shown when there are no export pipelines"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(exportPipelines) { pipeline in
                            PipelineInlineRow(
                                pipeline: pipeline,
                                isRunning: runningPipelineIDs.contains(pipeline.id),
                                hasTranscriptsForRun: hasTranscriptsForPipelineRun,
                                hasSelectedModel: selectedPipelineModelID != nil,
                                runFeedback: pipelineRunFeedbackByID[pipeline.id],
                                onRunNow: {
                                    runPipelineNow(pipeline)
                                },
                                onEdit: {
                                    beginEditPipelineFlow(pipeline)
                                },
                                onDelete: {
                                    pendingDeletePipeline = pipeline
                                }
                            )
                        }
                    }
                    .frame(minHeight: 170, maxHeight: 280)
                }

                if selectedPipelineModelID == nil {
                    Text(
                        localized(
                            "settings.ai.pipelines.noModel",
                            default: "Select an LM Studio model to run pipelines.",
                            comment: "Help text shown when no LM Studio model is selected for running pipelines"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if hasTranscriptsForPipelineRun == false {
                    Text(
                        localized(
                            "settings.ai.pipelines.noTranscripts",
                            default: "Run Now is available after at least one transcript exists.",
                            comment: "Help text shown when there are no transcripts available for pipeline run-now"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let pipelineErrorMessage {
                    Text(pipelineErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section(
                localized(
                    "settings.ai.webhooks.section",
                    default: "Webhooks",
                    comment: "Section title for webhook configuration and delivery log settings"
                )
            ) {
                Toggle(
                    localized(
                        "settings.ai.webhooks.enabled",
                        default: "Send webhook on new transcript",
                        comment: "Toggle label for enabling webhook delivery after transcript creation"
                    ),
                    isOn: Binding(
                        get: { webhookConfiguration.isEnabled },
                        set: { isEnabled in
                            updateWebhookConfiguration { $0.isEnabled = isEnabled }
                        }
                    )
                )

                if webhookConfiguration.isEnabled {
                    TextField(
                        localized(
                            "settings.ai.webhooks.endpoint",
                            default: "Endpoint URL",
                            comment: "Field label for webhook destination URL"
                        ),
                        text: Binding(
                            get: { webhookConfiguration.endpointURL },
                            set: { endpointURL in
                                updateWebhookConfiguration { $0.endpointURL = endpointURL }
                            }
                        ),
                        prompt: Text("https://hook.example.com/path")
                    )
                        .textFieldStyle(.roundedBorder)

                    TextField(
                        localized(
                            "settings.ai.webhooks.secret",
                            default: "Signing secret (optional)",
                            comment: "Field label for optional webhook HMAC signing secret"
                        ),
                        text: Binding(
                            get: { webhookConfiguration.hmacSecret },
                            set: { hmacSecret in
                                updateWebhookConfiguration { $0.hmacSecret = hmacSecret }
                            }
                        )
                    )
                        .textFieldStyle(.roundedBorder)

                    Toggle(
                        localized(
                            "settings.ai.webhooks.includeSpeakerMap",
                            default: "Include speaker names",
                            comment: "Toggle label for including speaker map in webhook payloads"
                        ),
                        isOn: Binding(
                            get: { webhookConfiguration.includeSpeakerMap },
                            set: { includeSpeakerMap in
                                updateWebhookConfiguration { $0.includeSpeakerMap = includeSpeakerMap }
                            }
                        )
                    )

                    Toggle(
                        localized(
                            "settings.ai.webhooks.includeSegments",
                            default: "Include time segments",
                            comment: "Toggle label for including transcript time segments in webhook payloads"
                        ),
                        isOn: Binding(
                            get: { webhookConfiguration.includeSegments },
                            set: { includeSegments in
                                updateWebhookConfiguration { $0.includeSegments = includeSegments }
                            }
                        )
                    )

                    HStack(spacing: 8) {
                        Button(
                            localized(
                                "settings.ai.webhooks.test",
                                default: "Test webhook",
                                comment: "Action title for sending a test webhook payload"
                            )
                        ) {
                            Task {
                                await sendWebhookTest()
                            }
                        }
                        .disabled(isSendingWebhookTest)

                        if isSendingWebhookTest {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let webhookURLValidationMessage {
                        Text(webhookURLValidationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let webhookTestMessage {
                        Text(webhookTestMessage)
                            .font(.caption)
                            .foregroundStyle(webhookTestMessageIsError ? .red : .secondary)
                    }

                    Text(
                        localized(
                            "settings.ai.webhooks.note",
                            default: "Waffle will POST JSON to this URL after each dictation and file import.",
                            comment: "Informational note describing when webhook payloads are sent"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(
                        localized(
                            "settings.ai.webhooks.secret.note",
                            default: "Keep this secret confidential.",
                            comment: "Security note shown below webhook HMAC secret field"
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Text(
                        localized(
                            "settings.ai.webhooks.recent.section",
                            default: "Recent Deliveries",
                            comment: "Subsection title for recent webhook delivery events"
                        )
                    )
                    .font(.subheadline.weight(.semibold))

                    Spacer()

                    Button(
                        localized(
                            "action.clear",
                            default: "Clear",
                            comment: "Action title for clearing a list"
                        )
                    ) {
                        webhookDeliveryLog.clear()
                        loadWebhookState()
                    }
                    .disabled(webhookDeliveryEntries.isEmpty)
                }

                if webhookDeliveryEntries.isEmpty {
                    Text(
                        localized(
                            "settings.ai.webhooks.recent.empty",
                            default: "No deliveries yet.",
                            comment: "Empty-state text shown when there are no webhook delivery entries"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(webhookDeliveryEntries.reversed()), id: \.id) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(entry.succeeded ? Color.green : Color.red)
                                .font(.caption)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entry.deliveredAt.formatted(date: .abbreviated, time: .shortened)) • \(entry.event)")
                                    .font(.caption)

                                Text(webhookDeliveryDetail(for: entry))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }
                }
            }

            SpeakerProfilesSection(transcriptStore: transcriptStore)
        }
        .padding()
        .task {
            await refreshModels()
            loadPromptTemplates()
            loadExportPipelines()
            loadWebhookState()
            await refreshLatestTranscriptAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            loadPromptTemplates()
            loadExportPipelines()
            loadWebhookState()
            Task {
                await refreshLatestTranscriptAvailability()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshLatestTranscriptAvailability()
            }
        }
        .sheet(isPresented: $isAddTemplateSheetPresented) {
            addTemplateSheet
        }
        .sheet(item: $pipelineEditorState) { state in
            PipelineEditorSheet(
                pipeline: state.pipeline,
                promptTemplates: promptTemplates,
                onSave: { pipeline in
                    savePipelineFromEditor(pipeline)
                }
            )
        }
        .alert(
            pendingDeleteTemplate?.name
                ?? localized(
                    "settings.ai.promptTemplates.delete.fallback",
                    default: "Delete template?",
                    comment: "Fallback title for delete template confirmation alert"
                ),
            isPresented: Binding(
                get: { pendingDeleteTemplate != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingDeleteTemplate = nil
                    }
                }
            )
        ) {
            Button(
                localized(
                    "action.delete",
                    default: "Delete",
                    comment: "Action title for deleting selected transcripts"
                ),
                role: .destructive
            ) {
                guard let pendingDeleteTemplate else { return }
                promptTemplateStore.delete(id: pendingDeleteTemplate.id)
                loadPromptTemplates()
                self.pendingDeleteTemplate = nil
            }

            Button(
                localized(
                    "action.cancel",
                    default: "Cancel",
                    comment: "Generic action title for canceling a dialog"
                ),
                role: .cancel
            ) {
                pendingDeleteTemplate = nil
            }
        } message: {
            if let pendingDeleteTemplate {
                Text(
                    localizedFormat(
                        "settings.ai.promptTemplates.delete.message",
                        default: "Delete \"%@\"? This cannot be undone.",
                        comment: "Confirmation message for deleting a prompt template",
                        pendingDeleteTemplate.name
                    )
                )
            }
        }
        .alert(
            pendingDeletePipeline?.name
                ?? localized(
                    "settings.ai.pipelines.delete.fallback",
                    default: "Delete pipeline?",
                    comment: "Fallback title for delete pipeline confirmation alert"
                ),
            isPresented: Binding(
                get: { pendingDeletePipeline != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingDeletePipeline = nil
                    }
                }
            )
        ) {
            Button(
                localized(
                    "action.delete",
                    default: "Delete",
                    comment: "Action title for deleting selected transcripts"
                ),
                role: .destructive
            ) {
                guard let pendingDeletePipeline else { return }
                exportPipelineStore.delete(id: pendingDeletePipeline.id)
                loadExportPipelines()
                pipelineRunFeedbackByID.removeValue(forKey: pendingDeletePipeline.id)
                self.pendingDeletePipeline = nil
            }

            Button(
                localized(
                    "action.cancel",
                    default: "Cancel",
                    comment: "Generic action title for canceling a dialog"
                ),
                role: .cancel
            ) {
                pendingDeletePipeline = nil
            }
        } message: {
            if let pendingDeletePipeline {
                Text(
                    localizedFormat(
                        "settings.ai.pipelines.delete.message",
                        default: "Delete \"%@\"? This cannot be undone.",
                        comment: "Confirmation message for deleting an export pipeline",
                        pendingDeletePipeline.name
                    )
                )
            }
        }
    }

    private var addTemplateSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                localized(
                    "settings.ai.promptTemplates.add.sheetTitle",
                    default: "Add Prompt Template",
                    comment: "Sheet title for adding a prompt template"
                )
            )
            .font(.headline)

            TextField(
                localized(
                    "settings.ai.promptTemplates.name",
                    default: "Name",
                    comment: "Label for prompt template name input"
                ),
                text: $newTemplateName
            )
            .textFieldStyle(.roundedBorder)

            TextEditor(text: $newTemplatePrompt)
                .frame(minHeight: 120)
                .font(.body)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            if let templateErrorMessage {
                Text(templateErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button(
                    localized(
                        "action.cancel",
                        default: "Cancel",
                        comment: "Generic action title for canceling a dialog"
                    )
                ) {
                    dismissAddTemplateSheet()
                }
                .buttonStyle(.bordered)

                Button(
                    localized(
                        "action.add",
                        default: "Add",
                        comment: "Action title for adding an item"
                    )
                ) {
                    saveTemplateFromSheet()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 300)
    }

    private func loadWebhookState() {
        webhookConfiguration = WebhookConfiguration.load()
        webhookDeliveryEntries = webhookDeliveryLog.load()
        webhookURLValidationMessage = webhookValidationMessage(for: webhookConfiguration)
    }

    private func updateWebhookConfiguration(_ update: (inout WebhookConfiguration) -> Void) {
        var updated = webhookConfiguration
        update(&updated)
        webhookConfiguration = updated
        persistWebhookConfigurationIfValid()
    }

    private func persistWebhookConfigurationIfValid() {
        let validationMessage = webhookValidationMessage(for: webhookConfiguration)
        webhookURLValidationMessage = validationMessage

        guard validationMessage == nil else { return }
        WebhookConfiguration.save(webhookConfiguration)
    }

    private func webhookValidationMessage(for configuration: WebhookConfiguration) -> String? {
        guard configuration.isEnabled else { return nil }
        let endpoint = configuration.trimmedEndpointURL

        guard endpoint.isEmpty == false else {
            return localized(
                "settings.ai.webhooks.validation.endpointRequired",
                default: "Endpoint URL is required when webhook delivery is enabled.",
                comment: "Validation message shown when webhook delivery is enabled without an endpoint URL"
            )
        }

        guard configuration.validatedEndpointURL != nil else {
            return localized(
                "settings.ai.webhooks.validation.endpointInvalid",
                default: "Endpoint URL must be a valid https:// URL.",
                comment: "Validation message shown when webhook endpoint URL is invalid or uses a non-HTTPS scheme"
            )
        }

        return nil
    }

    private func sendWebhookTest() async {
        webhookTestMessage = nil
        webhookTestMessageIsError = false

        guard webhookValidationMessage(for: webhookConfiguration) == nil else {
            webhookURLValidationMessage = webhookValidationMessage(for: webhookConfiguration)
            webhookTestMessage = localized(
                "settings.ai.webhooks.test.validationFailed",
                default: "Fix the webhook URL before sending a test payload.",
                comment: "Message shown when test webhook is attempted with invalid endpoint settings"
            )
            webhookTestMessageIsError = true
            return
        }

        WebhookConfiguration.save(webhookConfiguration)

        isSendingWebhookTest = true
        defer {
            isSendingWebhookTest = false
            loadWebhookState()
        }

        do {
            let statusCode = try await webhookService.sendTestPayload(config: webhookConfiguration)
            let succeeded = (200...299).contains(statusCode)

            webhookTestMessage = succeeded
                ? localizedFormat(
                    "settings.ai.webhooks.test.success",
                    default: "Test webhook delivered (HTTP %d).",
                    comment: "Status message shown when a test webhook call succeeds",
                    statusCode
                )
                : localizedFormat(
                    "settings.ai.webhooks.test.nonSuccessStatus",
                    default: "Test webhook responded with HTTP %d.",
                    comment: "Status message shown when a test webhook returns a non-success status code",
                    statusCode
                )
            webhookTestMessageIsError = succeeded == false
        } catch {
            webhookTestMessage = localizedFormat(
                "settings.ai.webhooks.test.failure",
                default: "Test webhook failed: %@",
                comment: "Status message shown when a test webhook request fails with an error",
                error.localizedDescription
            )
            webhookTestMessageIsError = true
        }
    }

    private func webhookDeliveryDetail(for entry: WebhookDeliveryEntry) -> String {
        if let statusCode = entry.statusCode {
            return "HTTP \(statusCode)"
        }

        if let errorMessage = entry.errorMessage, errorMessage.isEmpty == false {
            return errorMessage
        }

        return localized(
            "settings.ai.webhooks.recent.noResponse",
            default: "No response received.",
            comment: "Fallback detail shown for webhook delivery entries that have no status code or error text"
        )
    }

    private func loadPromptTemplates() {
        promptTemplates = promptTemplateStore.load()
    }

    private func loadExportPipelines() {
        exportPipelines = exportPipelineStore.load()
        let validIDs = Set(exportPipelines.map(\.id))
        runningPipelineIDs = runningPipelineIDs.intersection(validIDs)
        pipelineRunFeedbackByID = pipelineRunFeedbackByID.filter { validIDs.contains($0.key) }
    }

    private var selectedPipelineModelID: String? {
        let trimmed = lmStudioModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func beginAddPipelineFlow() {
        guard exportPipelines.count < ExportPipelineStore.maxPipelineCount else {
            pipelineErrorMessage = localizedFormat(
                "settings.ai.pipelines.limit",
                default: "You can save up to %d pipelines.",
                comment: "Validation message shown when export pipeline limit is reached",
                ExportPipelineStore.maxPipelineCount
            )
            return
        }

        pipelineErrorMessage = nil
        pipelineEditorState = PipelineEditorState(pipeline: nil)
    }

    private func beginEditPipelineFlow(_ pipeline: ExportPipeline) {
        pipelineErrorMessage = nil
        pipelineEditorState = PipelineEditorState(pipeline: pipeline)
    }

    private func savePipelineFromEditor(_ pipeline: ExportPipeline) {
        let pipelineExists = exportPipelines.contains(where: { $0.id == pipeline.id })

        if pipelineExists {
            exportPipelineStore.update(pipeline)
        } else {
            exportPipelineStore.add(pipeline)
        }

        loadExportPipelines()
        pipelineErrorMessage = nil
    }

    private func runPipelineNow(_ pipeline: ExportPipeline) {
        guard runningPipelineIDs.contains(pipeline.id) == false else { return }
        guard let transcriptStore else {
            pipelineRunFeedbackByID[pipeline.id] = PipelineRunFeedback(
                message: localized(
                    "settings.ai.pipelines.run.storeUnavailable",
                    default: "Transcript history is unavailable.",
                    comment: "Run-now error shown when transcript storage is unavailable"
                ),
                isError: true
            )
            return
        }
        guard let modelID = selectedPipelineModelID else {
            pipelineRunFeedbackByID[pipeline.id] = PipelineRunFeedback(
                message: localized(
                    "settings.ai.pipelines.run.noModel",
                    default: "Select an LM Studio model first.",
                    comment: "Run-now error shown when no LM Studio model is selected"
                ),
                isError: true
            )
            return
        }
        guard let actionService = makeTranscriptActionService() else {
            pipelineRunFeedbackByID[pipeline.id] = PipelineRunFeedback(
                message: localized(
                    "settings.ai.pipelines.run.connectionRequired",
                    default: "LM Studio host and port must be valid before running pipelines.",
                    comment: "Run-now error shown when LM Studio connection settings are invalid"
                ),
                isError: true
            )
            return
        }

        runningPipelineIDs.insert(pipeline.id)
        pipelineRunFeedbackByID[pipeline.id] = nil
        pipelineErrorMessage = nil

        Task {
            let latestTranscript = await Task.detached(priority: .utility) {
                try? transcriptStore.fetchAll(limit: 1).first
            }.value

            guard let latestTranscript else {
                await MainActor.run {
                    runningPipelineIDs.remove(pipeline.id)
                    pipelineRunFeedbackByID[pipeline.id] = PipelineRunFeedback(
                        message: localized(
                            "settings.ai.pipelines.run.noTranscripts",
                            default: "No transcripts available to process.",
                            comment: "Run-now message shown when there are no transcripts yet"
                        ),
                        isError: true
                    )
                    hasTranscriptsForPipelineRun = false
                }
                return
            }

            let runner = ExportPipelineRunner(
                actionService: actionService,
                transcriptStore: transcriptStore
            )

            do {
                let finalText = try await runner.run(
                    pipeline: pipeline,
                    transcript: latestTranscript,
                    modelID: modelID
                )

                await MainActor.run {
                    applyOutputDestination(finalText, destination: pipeline.outputDestination)
                    runningPipelineIDs.remove(pipeline.id)
                    pipelineRunFeedbackByID[pipeline.id] = PipelineRunFeedback(
                        message: localized(
                            "settings.ai.pipelines.run.success",
                            default: "Pipeline completed.",
                            comment: "Run-now status shown after a successful pipeline run"
                        ),
                        isError: false
                    )
                    hasTranscriptsForPipelineRun = true
                }
            } catch {
                await MainActor.run {
                    runningPipelineIDs.remove(pipeline.id)
                    pipelineRunFeedbackByID[pipeline.id] = PipelineRunFeedback(
                        message: localizedFormat(
                            "settings.ai.pipelines.run.failure",
                            default: "Pipeline failed: %@",
                            comment: "Run-now status shown when a pipeline run fails",
                            error.localizedDescription
                        ),
                        isError: true
                    )
                }
            }
        }
    }

    private func makeTranscriptActionService() -> TranscriptActionService? {
        let host = lmStudioHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard host.isEmpty == false else { return nil }
        guard let port = Int(lmStudioPort), port > 0 else { return nil }

        let client = LMStudioClient(
            configuration: LMStudioConfiguration(host: host, port: port)
        )
        return TranscriptActionService(lmStudioClient: client)
    }

    private func refreshLatestTranscriptAvailability() async {
        guard let transcriptStore else {
            hasTranscriptsForPipelineRun = false
            return
        }

        let hasTranscripts = await Task.detached(priority: .utility) {
            (try? transcriptStore.fetchAll(limit: 1).isEmpty == false) ?? false
        }.value
        hasTranscriptsForPipelineRun = hasTranscripts
    }

    private func applyOutputDestination(_ text: String, destination: ExportPipelineOutputDestination) {
        switch destination {
        case .clipboard:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .none:
            break
        }
    }

    private func beginAddTemplateFlow() {
        guard promptTemplates.count < PromptTemplateStore.maxTemplateCount else {
            templateErrorMessage = localizedFormat(
                "settings.ai.promptTemplates.limit",
                default: "You can save up to %d templates.",
                comment: "Validation message shown when prompt template limit is reached",
                PromptTemplateStore.maxTemplateCount
            )
            return
        }

        newTemplateName = ""
        newTemplatePrompt = ""
        templateErrorMessage = nil
        isAddTemplateSheetPresented = true
    }

    private func dismissAddTemplateSheet() {
        isAddTemplateSheetPresented = false
        newTemplateName = ""
        newTemplatePrompt = ""
    }

    private func saveTemplateFromSheet() {
        let normalizedName = newTemplateName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = newTemplatePrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedName.isEmpty == false else {
            templateErrorMessage = localized(
                "settings.ai.promptTemplates.validation.nameRequired",
                default: "Template name is required.",
                comment: "Validation message shown when a template name is missing"
            )
            return
        }

        guard normalizedName.count <= 40 else {
            templateErrorMessage = localized(
                "settings.ai.promptTemplates.validation.nameLength",
                default: "Template name must be 40 characters or fewer.",
                comment: "Validation message shown when template name exceeds maximum length"
            )
            return
        }

        guard normalizedPrompt.isEmpty == false else {
            templateErrorMessage = localized(
                "settings.ai.promptTemplates.validation.promptRequired",
                default: "Prompt text is required.",
                comment: "Validation message shown when template prompt text is missing"
            )
            return
        }

        guard promptTemplates.count < PromptTemplateStore.maxTemplateCount else {
            templateErrorMessage = localizedFormat(
                "settings.ai.promptTemplates.limit",
                default: "You can save up to %d templates.",
                comment: "Validation message shown when prompt template limit is reached",
                PromptTemplateStore.maxTemplateCount
            )
            return
        }

        _ = promptTemplateStore.add(name: normalizedName, prompt: normalizedPrompt)
        loadPromptTemplates()
        templateErrorMessage = nil
        dismissAddTemplateSheet()
    }

    private func updatePromptTemplate(_ template: PromptTemplate) {
        promptTemplateStore.update(template)
        loadPromptTemplates()
        templateErrorMessage = nil
    }

    private func movePromptTemplates(from source: IndexSet, to destination: Int) {
        var reordered = promptTemplates
        reordered.move(fromOffsets: source, toOffset: destination)
        promptTemplateStore.save(reordered)
        loadPromptTemplates()
    }

    private func refreshModels() async {
        isTestingConnection = true
        defer { isTestingConnection = false }

        let host = lmStudioHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard host.isEmpty == false else {
            isConnected = false
            connectionMessage = localized(
                "settings.ai.connection.enterHost",
                default: "Enter a host to connect.",
                comment: "Connection status prompting for host input"
            )
            availableModels = []
            return
        }

        guard let port = Int(lmStudioPort), port > 0 else {
            isConnected = false
            connectionMessage = localized(
                "settings.ai.connection.invalidPort",
                default: "Port must be a valid number.",
                comment: "Connection status error for invalid LM Studio port"
            )
            availableModels = []
            return
        }

        let client = LMStudioClient(
            configuration: LMStudioConfiguration(host: host, port: port)
        )

        do {
            let models = try await client.fetchModels()
            availableModels = models
            isConnected = true
            connectionMessage = localized(
                "settings.ai.connection.success",
                default: "Connection successful.",
                comment: "Connection status shown when LM Studio test succeeds"
            )

            if models.contains(where: { $0.id == lmStudioModelID }) == false {
                lmStudioModelID = models.first?.id ?? ""
            }
        } catch LMStudioClientError.noModelsLoaded {
            availableModels = []
            isConnected = true
            connectionMessage = localized(
                "settings.ai.connection.noModels",
                default: "Connected, but no models are loaded in LM Studio.",
                comment: "Connection status shown when LM Studio is reachable but has no loaded models"
            )
            lmStudioModelID = ""
        } catch {
            availableModels = []
            isConnected = false
            connectionMessage = connectionErrorMessage(for: error)
            lmStudioModelID = ""
        }
    }

    private func connectionErrorMessage(for error: Error) -> String {
        switch error {
        case LMStudioClientError.connectionRefused:
            return localized(
                "error.lmStudio.unreachable",
                default: "LM Studio is not running or unreachable.",
                comment: "Error shown when LM Studio cannot be reached"
            )
        case LMStudioClientError.unexpectedStatusCode(let code):
            return localizedFormat(
                "error.lmStudio.statusCode",
                default: "LM Studio returned status code %d.",
                comment: "Error shown when LM Studio returns an unexpected HTTP status code",
                code
            )
        default:
            return localized(
                "error.connectionTestFailed",
                default: "Connection test failed.",
                comment: "Error shown when LM Studio connection test fails for an unknown reason"
            )
        }
    }
}

private struct PromptTemplateInlineRow: View {
    let template: PromptTemplate
    let onUpdate: (PromptTemplate) -> Void
    let onRequestDelete: (PromptTemplate) -> Void
    let onValidationError: (String?) -> Void

    @State private var isEditingName = false
    @State private var isEditingPrompt = false
    @State private var nameDraft: String
    @State private var promptDraft: String

    init(
        template: PromptTemplate,
        onUpdate: @escaping (PromptTemplate) -> Void,
        onRequestDelete: @escaping (PromptTemplate) -> Void,
        onValidationError: @escaping (String?) -> Void
    ) {
        self.template = template
        self.onUpdate = onUpdate
        self.onRequestDelete = onRequestDelete
        self.onValidationError = onValidationError
        _nameDraft = State(initialValue: template.name)
        _promptDraft = State(initialValue: template.prompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if isEditingName {
                    TextField(
                        localized(
                            "settings.ai.promptTemplates.name",
                            default: "Name",
                            comment: "Label for prompt template name input"
                        ),
                        text: $nameDraft
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        commitNameEdit()
                    }
                } else {
                    Text(template.name)
                        .font(.body.weight(.semibold))
                        .onTapGesture {
                            onValidationError(nil)
                            nameDraft = template.name
                            isEditingName = true
                        }
                }

                Spacer()

                Button {
                    onRequestDelete(template)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            if isEditingPrompt {
                TextEditor(text: $promptDraft)
                    .frame(minHeight: 70, maxHeight: 110)
                    .font(.caption)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    Button(
                        localized(
                            "action.save",
                            default: "Save",
                            comment: "Generic action title for saving data"
                        )
                    ) {
                        commitPromptEdit()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button(
                        localized(
                            "action.cancel",
                            default: "Cancel",
                            comment: "Generic action title for canceling a dialog"
                        )
                    ) {
                        promptDraft = template.prompt
                        isEditingPrompt = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Text(promptPreview(for: template.prompt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .onTapGesture {
                        onValidationError(nil)
                        promptDraft = template.prompt
                        isEditingPrompt = true
                    }
            }
        }
        .onChange(of: template) { _, updated in
            if isEditingName == false {
                nameDraft = updated.name
            }
            if isEditingPrompt == false {
                promptDraft = updated.prompt
            }
        }
    }

    private func commitNameEdit() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            onValidationError(
                localized(
                    "settings.ai.promptTemplates.validation.nameRequired",
                    default: "Template name is required.",
                    comment: "Validation message shown when a template name is missing"
                )
            )
            nameDraft = template.name
            isEditingName = false
            return
        }

        guard trimmed.count <= 40 else {
            onValidationError(
                localized(
                    "settings.ai.promptTemplates.validation.nameLength",
                    default: "Template name must be 40 characters or fewer.",
                    comment: "Validation message shown when template name exceeds maximum length"
                )
            )
            nameDraft = template.name
            isEditingName = false
            return
        }

        var updated = template
        updated.name = trimmed
        onUpdate(updated)
        onValidationError(nil)
        isEditingName = false
    }

    private func commitPromptEdit() {
        let trimmed = promptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            onValidationError(
                localized(
                    "settings.ai.promptTemplates.validation.promptRequired",
                    default: "Prompt text is required.",
                    comment: "Validation message shown when template prompt text is missing"
                )
            )
            promptDraft = template.prompt
            isEditingPrompt = false
            return
        }

        var updated = template
        updated.prompt = trimmed
        onUpdate(updated)
        onValidationError(nil)
        isEditingPrompt = false
    }

    private func promptPreview(for prompt: String) -> String {
        let compact = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count <= 60 { return compact }
        return String(compact.prefix(60)) + "…"
    }
}

private struct PipelineEditorState: Identifiable {
    let id: UUID
    let pipeline: ExportPipeline?

    init(pipeline: ExportPipeline?) {
        self.id = UUID()
        self.pipeline = pipeline
    }
}

private struct PipelineRunFeedback: Equatable {
    let message: String
    let isError: Bool
}

private struct PipelineInlineRow: View {
    let pipeline: ExportPipeline
    let isRunning: Bool
    let hasTranscriptsForRun: Bool
    let hasSelectedModel: Bool
    let runFeedback: PipelineRunFeedback?
    let onRunNow: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(pipeline.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Text(
                    localizedFormat(
                        "settings.ai.pipelines.steps.count",
                        default: "%d step%@",
                        comment: "Step-count badge for pipeline list rows",
                        pipeline.steps.count,
                        pipeline.steps.count == 1 ? "" : "s"
                    )
                )
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())

                if pipeline.runAutomatically {
                    Text(
                        localized(
                            "settings.ai.pipelines.autoBadge",
                            default: "Auto",
                            comment: "Badge shown on pipelines configured to run automatically"
                        )
                    )
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                }

                Spacer()

                Button(
                    localized(
                        "settings.ai.pipelines.runNow",
                        default: "Run Now",
                        comment: "Button title for running a pipeline immediately"
                    )
                ) {
                    onRunNow()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRunning || hasTranscriptsForRun == false || hasSelectedModel == false)

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Text(
                    localizedFormat(
                        "settings.ai.pipelines.output",
                        default: "Output: %@",
                        comment: "Pipeline row subtitle describing output destination",
                        outputDestinationLabel(pipeline.outputDestination)
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let runFeedback {
                Text(runFeedback.message)
                    .font(.caption)
                    .foregroundStyle(runFeedback.isError ? .red : .green)
            }
        }
        .padding(.vertical, 4)
    }

    private func outputDestinationLabel(_ destination: ExportPipelineOutputDestination) -> String {
        switch destination {
        case .clipboard:
            return localized(
                "settings.ai.pipelines.output.clipboard",
                default: "Copy final output to clipboard",
                comment: "Output destination label for clipboard delivery"
            )
        case .none:
            return localized(
                "settings.ai.pipelines.output.none",
                default: "Save to action log only",
                comment: "Output destination label for no clipboard delivery"
            )
        }
    }
}

private struct PipelineEditorSheet: View {
    let pipeline: ExportPipeline?
    let promptTemplates: [PromptTemplate]
    let onSave: (ExportPipeline) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var steps: [ExportPipelineStep]
    @State private var runAutomatically: Bool
    @State private var outputDestination: ExportPipelineOutputDestination
    @State private var validationMessage: String?

    init(
        pipeline: ExportPipeline?,
        promptTemplates: [PromptTemplate],
        onSave: @escaping (ExportPipeline) -> Void
    ) {
        self.pipeline = pipeline
        self.promptTemplates = promptTemplates
        self.onSave = onSave
        _name = State(initialValue: pipeline?.name ?? "")
        _steps = State(initialValue: pipeline?.steps ?? [])
        _runAutomatically = State(initialValue: pipeline?.runAutomatically ?? false)
        _outputDestination = State(initialValue: pipeline?.outputDestination ?? .none)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                pipeline == nil
                    ? localized(
                        "settings.ai.pipelines.editor.addTitle",
                        default: "Add Pipeline",
                        comment: "Sheet title when creating a new export pipeline"
                    )
                    : localized(
                        "settings.ai.pipelines.editor.editTitle",
                        default: "Edit Pipeline",
                        comment: "Sheet title when editing an existing export pipeline"
                    )
            )
            .font(.headline)

            TextField(
                localized(
                    "settings.ai.pipelines.editor.name",
                    default: "Name",
                    comment: "Field label for export pipeline name"
                ),
                text: $name
            )
            .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(
                        localized(
                            "settings.ai.pipelines.editor.steps",
                            default: "Steps",
                            comment: "Subsection title for pipeline step list in editor sheet"
                        )
                    )
                    .font(.subheadline.weight(.semibold))

                    Spacer()

                    if steps.count < ExportPipeline.maxStepCount {
                        Menu(
                            localized(
                                "settings.ai.pipelines.editor.addStep",
                                default: "Add Step",
                                comment: "Menu button title for adding a prompt-template step to a pipeline"
                            )
                        ) {
                            if promptTemplates.isEmpty {
                                Text(
                                    localized(
                                        "settings.ai.promptTemplates.empty.short",
                                        default: "No templates saved",
                                        comment: "Short empty-state text shown in template picker menus"
                                    )
                                )
                                .disabled(true)
                            } else {
                                ForEach(promptTemplates) { template in
                                    Button(template.name) {
                                        addStep(from: template)
                                    }
                                }
                            }
                        }
                    }
                }

                Text(
                    localized(
                        "settings.ai.pipelines.editor.steps.help",
                        default: "Drag rows to reorder steps.",
                        comment: "Help text explaining how to reorder pipeline steps in the editor"
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                List {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .center, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)

                            Text(displayName(for: step))
                                .font(.body)
                                .lineLimit(1)

                            Spacer()

                            Button {
                                removeStep(id: step.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                    }
                    .onMove(perform: moveSteps)
                }
                .frame(minHeight: 180, maxHeight: 260)
            }

            Toggle(
                localized(
                    "settings.ai.pipelines.editor.autoRun",
                    default: "Run automatically after each transcription",
                    comment: "Toggle label for enabling automatic pipeline execution after transcription"
                ),
                isOn: $runAutomatically
            )

            Picker(
                localized(
                    "settings.ai.pipelines.editor.output",
                    default: "Output",
                    comment: "Picker label for selecting export pipeline output destination"
                ),
                selection: $outputDestination
            ) {
                Text(
                    localized(
                        "settings.ai.pipelines.output.none",
                        default: "Save to action log only",
                        comment: "Output destination label for no clipboard delivery"
                    )
                )
                .tag(ExportPipelineOutputDestination.none)

                Text(
                    localized(
                        "settings.ai.pipelines.output.clipboard",
                        default: "Copy final output to clipboard",
                        comment: "Output destination label for clipboard delivery"
                    )
                )
                .tag(ExportPipelineOutputDestination.clipboard)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button(
                    localized(
                        "action.cancel",
                        default: "Cancel",
                        comment: "Generic action title for canceling a dialog"
                    )
                ) {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(
                    localized(
                        "action.save",
                        default: "Save",
                        comment: "Generic action title for saving data"
                    )
                ) {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 540, minHeight: 520)
    }

    private var promptTemplatesByID: [UUID: PromptTemplate] {
        Dictionary(uniqueKeysWithValues: promptTemplates.map { ($0.id, $0) })
    }

    private func displayName(for step: ExportPipelineStep) -> String {
        if promptTemplatesByID[step.templateID] == nil {
            return "\(step.templateName) (deleted)"
        }
        return step.templateName
    }

    private func addStep(from template: PromptTemplate) {
        guard steps.count < ExportPipeline.maxStepCount else { return }
        steps.append(
            ExportPipelineStep(
                templateID: template.id,
                templateName: template.name,
                templatePrompt: template.prompt
            )
        )
        validationMessage = nil
    }

    private func removeStep(id: UUID) {
        steps.removeAll { $0.id == id }
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        steps.move(fromOffsets: source, toOffset: destination)
    }

    private func save() {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else {
            validationMessage = localized(
                "settings.ai.pipelines.validation.nameRequired",
                default: "Pipeline name is required.",
                comment: "Validation message shown when a pipeline name is missing"
            )
            return
        }

        guard steps.isEmpty == false else {
            validationMessage = localized(
                "settings.ai.pipelines.validation.stepsRequired",
                default: "Add at least one step.",
                comment: "Validation message shown when saving a pipeline with no steps"
            )
            return
        }

        let refreshedSteps = steps.map { step in
            guard let template = promptTemplatesByID[step.templateID] else { return step }
            return ExportPipelineStep(
                id: step.id,
                templateID: template.id,
                templateName: template.name,
                templatePrompt: template.prompt
            )
        }

        onSave(
            ExportPipeline(
                id: pipeline?.id ?? UUID(),
                name: normalizedName,
                steps: refreshedSteps,
                runAutomatically: runAutomatically,
                outputDestination: outputDestination,
                createdAt: pipeline?.createdAt ?? Date()
            )
        )
        dismiss()
    }
}

private struct ModelRowView: View {
    let entry: ModelCatalogEntry
    @ObservedObject var modelStore: ModelStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.displayName)
                        .font(.headline)

                    if modelStore.resolvedSelectedModelID == entry.id {
                        Text(
                            localized(
                                "settings.models.badge.inUse",
                                default: "In Use",
                                comment: "Badge shown for the currently selected model"
                            )
                        )
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }

                    if modelStore.isInstalled(entry) {
                        Text(
                            localized(
                                "settings.models.badge.installed",
                                default: "Installed",
                                comment: "Badge shown for a model installed on disk"
                            )
                        )
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12), in: Capsule())
                            .accessibilityLabel(
                                localized(
                                    "settings.models.downloadState.installed",
                                    default: "Model installed",
                                    comment: "Accessibility label announcing installed model state"
                                )
                            )
                    } else if entry.available == false {
                        Text(
                            localized(
                                "settings.models.badge.comingSoon",
                                default: "Coming Soon",
                                comment: "Badge shown for a model that is not downloadable yet"
                            )
                        )
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .accessibilityLabel(
                                localized(
                                    "settings.models.downloadState.unavailable",
                                    default: "Model unavailable",
                                    comment: "Accessibility label announcing unavailable model state"
                                )
                            )
                    }
                }

                Text(
                    localized(
                        "settings.models.metadata",
                        default: "\(entry.sizeMB) MB • \(entry.languageCount) language\(entry.languageCount == 1 ? "" : "s")",
                        comment: "Model metadata showing size and supported language count"
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if modelStore.activeDownloadID == entry.id {
                    ProgressView(value: modelStore.progress(for: entry.id))
                        .frame(maxWidth: 180)
                        .accessibilityLabel(
                            localizedFormat(
                                "settings.models.downloadState.progress",
                                default: "Downloading %@, %d percent",
                                comment: "Accessibility label describing model download progress",
                                entry.id,
                                Int((modelStore.progress(for: entry.id) * 100).rounded())
                            )
                        )
                }

                if let errorMessage = modelStore.errorMessage(for: entry.id) {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if modelStore.isInstalled(entry) {
                Button(
                    localized(
                        "action.remove",
                        default: "Remove",
                        comment: "Action title for removing an installed model"
                    )
                ) {
                    modelStore.removeInstalledModel(id: entry.id)
                }
                .buttonStyle(.bordered)
            } else {
                Button(
                    entry.available
                        ? localized(
                            "action.download",
                            default: "Download",
                            comment: "Action title for starting model download"
                        )
                        : localized(
                            "status.unavailable",
                            default: "Unavailable",
                            comment: "Status text for models that cannot be downloaded"
                        )
                ) {
                    modelStore.download(entry: entry)
                }
                .buttonStyle(.borderedProminent)
                .disabled(entry.available == false || modelStore.activeDownloadID != nil)
            }
        }
        .padding(.vertical, 6)
    }
}

struct KeyboardSettingsView: View {
    @AppStorage("globalHotkey") private var hotkeyStorage = ""
    let onUpdateHotkey: (GlobalHotkey) -> Void

    @State private var currentHotkey = GlobalHotkey.optionSpace
    @State private var validationMessage: String?

    var body: some View {
        Form {
            HotkeyRecorderView(
                currentHotkey: currentHotkey,
                onHotkeyCaptured: { hotkey in
                    save(hotkey: hotkey)
                },
                validationMessage: validationMessage,
                setValidationMessage: { validationMessage = $0 }
            )

            Button(
                localized(
                    "settings.keyboard.resetDefault",
                    default: "Reset to Default",
                    comment: "Action title for resetting global hotkey to default"
                )
            ) {
                save(hotkey: .optionSpace)
            }
            .buttonStyle(.bordered)

            Text(
                localized(
                    "settings.keyboard.help",
                    default: "Shortcuts must include at least one modifier key. Avoid common Spotlight shortcuts like ⌘Space.",
                    comment: "Help text describing global hotkey requirements"
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear {
            loadStoredHotkey()
        }
    }

    private func loadStoredHotkey() {
        guard
            hotkeyStorage.isEmpty == false,
            let storedHotkey = GlobalHotkey.decoded(from: hotkeyStorage)
        else {
            save(hotkey: .optionSpace)
            return
        }
        currentHotkey = storedHotkey
        validationMessage = nil
    }

    private func save(hotkey: GlobalHotkey) {
        guard let encoded = hotkey.encodedJSONString() else {
            validationMessage = localized(
                "error.hotkey.saveFailed",
                default: "Could not save this shortcut.",
                comment: "Error shown when global hotkey cannot be saved"
            )
            return
        }
        hotkeyStorage = encoded
        currentHotkey = hotkey
        validationMessage = nil
        onUpdateHotkey(hotkey)
    }
}

struct AppLanguageOption: Identifiable, Sendable {
    let name: String
    let code: String

    var id: String { code }

    static let defaultCode = "en"

    static let all: [AppLanguageOption] = [
        AppLanguageOption(
            name: localized(
                "settings.language.english",
                default: "English",
                comment: "Language option label for English"
            ),
            code: "en"
        ),
        AppLanguageOption(
            name: localized(
                "settings.language.spanish",
                default: "Spanish",
                comment: "Language option label for Spanish"
            ),
            code: "es"
        ),
        AppLanguageOption(
            name: localized(
                "settings.language.french",
                default: "French",
                comment: "Language option label for French"
            ),
            code: "fr"
        ),
        AppLanguageOption(
            name: localized(
                "settings.language.german",
                default: "German",
                comment: "Language option label for German"
            ),
            code: "de"
        ),
        AppLanguageOption(
            name: localized(
                "settings.language.italian",
                default: "Italian",
                comment: "Language option label for Italian"
            ),
            code: "it"
        ),
        AppLanguageOption(
            name: localized(
                "settings.language.portuguese",
                default: "Portuguese",
                comment: "Language option label for Portuguese"
            ),
            code: "pt"
        ),
        AppLanguageOption(
            name: localized(
                "settings.language.chinese",
                default: "Chinese",
                comment: "Language option label for Chinese"
            ),
            code: "zh"
        ),
        AppLanguageOption(
            name: localized(
                "settings.language.japanese",
                default: "Japanese",
                comment: "Language option label for Japanese"
            ),
            code: "ja"
        ),
        AppLanguageOption(
            name: localized(
                "settings.language.korean",
                default: "Korean",
                comment: "Language option label for Korean"
            ),
            code: "ko"
        ),
        AppLanguageOption(
            name: localized(
                "settings.language.russian",
                default: "Russian",
                comment: "Language option label for Russian"
            ),
            code: "ru"
        ),
        AppLanguageOption(
            name: localized(
                "settings.language.arabic",
                default: "Arabic",
                comment: "Language option label for Arabic"
            ),
            code: "ar"
        ),
        AppLanguageOption(
            name: localized(
                "settings.language.hindi",
                default: "Hindi",
                comment: "Language option label for Hindi"
            ),
            code: "hi"
        ),
    ]
}

private struct HotkeyRecorderView: View {
    let currentHotkey: GlobalHotkey
    let onHotkeyCaptured: (GlobalHotkey) -> Void
    let validationMessage: String?
    let setValidationMessage: (String?) -> Void

    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(
                localized(
                    "settings.keyboard.globalHotkey",
                    default: "Global Hotkey",
                    comment: "Label for currently configured global hotkey"
                )
            ) {
                Text(currentHotkey.displayValue)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel(
                        localizedFormat(
                            "settings.keyboard.globalHotkey.value",
                            default: "Current global hotkey %@",
                            comment: "Accessibility label describing the current global hotkey value",
                            currentHotkey.displayValue
                        )
                    )
            }

            HStack(spacing: 12) {
                Button(
                    isRecording
                        ? localized(
                            "settings.keyboard.recordingButton.recording",
                            default: "Press your shortcut…",
                            comment: "Button title while waiting for hotkey capture"
                        )
                        : localized(
                            "settings.keyboard.recordingButton.change",
                            default: "Change…",
                            comment: "Button title to start changing the global hotkey"
                        )
                ) {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
                .buttonStyle(.borderedProminent)

                if isRecording {
                    Text(
                        localized(
                            "settings.keyboard.recordingPrompt",
                            default: "Press your shortcut…",
                            comment: "Prompt shown while waiting for user to press a new hotkey"
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        setValidationMessage(nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            capture(event: event)
            return nil
        }
    }

    private func stopRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        isRecording = false
    }

    private func capture(event: NSEvent) {
        let keyCode = CGKeyCode(event.keyCode)
        let modifiers = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            .intersection(GlobalHotkey.supportedModifiers)

        let requiredModifiers: CGEventFlags = [
            .maskCommand,
            .maskAlternate,
            .maskControl,
            .maskShift,
        ]
        if modifiers.intersection(requiredModifiers).isEmpty {
            setValidationMessage(
                localized(
                    "settings.keyboard.validation.modifierRequired",
                    default: "Shortcut must include at least one modifier (⌘, ⌥, ⌃, ⇧).",
                    comment: "Validation message shown when captured shortcut has no required modifiers"
                )
            )
            return
        }

        if conflictsWithSystemShortcut(keyCode: keyCode, modifiers: modifiers) {
            setValidationMessage(
                localized(
                    "settings.keyboard.validation.systemConflict",
                    default: "That shortcut likely conflicts with a system shortcut. Try a different combo.",
                    comment: "Validation message shown when captured shortcut likely conflicts with system shortcuts"
                )
            )
            return
        }

        let capturedHotkey = GlobalHotkey(
            keyCode: keyCode,
            modifiers: modifiers,
            displayValue: displayValue(for: keyCode, modifiers: modifiers, fallbackEvent: event)
        )
        onHotkeyCaptured(capturedHotkey)
        stopRecording()
    }

    private func conflictsWithSystemShortcut(
        keyCode: CGKeyCode,
        modifiers: CGEventFlags
    ) -> Bool {
        let requiredModifiers = modifiers.intersection([.maskCommand, .maskControl, .maskShift])
        if keyCode == CGKeyCode(kVK_Space) {
            return requiredModifiers == [.maskCommand]
                || requiredModifiers == [.maskCommand, .maskShift]
                || requiredModifiers == [.maskControl]
        }
        return false
    }

    private func displayValue(
        for keyCode: CGKeyCode,
        modifiers: CGEventFlags,
        fallbackEvent: NSEvent
    ) -> String {
        var value = ""
        if modifiers.contains(.maskControl) { value += "⌃" }
        if modifiers.contains(.maskAlternate) { value += "⌥" }
        if modifiers.contains(.maskShift) { value += "⇧" }
        if modifiers.contains(.maskCommand) { value += "⌘" }
        if modifiers.contains(.maskSecondaryFn) { value += "fn" }
        value += keyLabel(for: keyCode, fallbackEvent: fallbackEvent)
        return value
    }

    private func keyLabel(for keyCode: CGKeyCode, fallbackEvent: NSEvent) -> String {
        if let mapped = Self.keyLabelMap[keyCode] {
            return mapped
        }

        if let characters = fallbackEvent.charactersIgnoringModifiers,
           characters.isEmpty == false {
            return characters.uppercased()
        }

        return localizedFormat(
            "settings.keyboard.keyLabel.generic",
            default: "Key%d",
            comment: "Fallback key label when a key code has no friendly name",
            Int(keyCode)
        )
    }

    private static let keyLabelMap: [CGKeyCode: String] = [
        CGKeyCode(kVK_Return): localized(
            "settings.keyboard.keyLabel.return",
            default: "Return",
            comment: "Display label for Return key in hotkey recorder"
        ),
        CGKeyCode(kVK_Tab): localized(
            "settings.keyboard.keyLabel.tab",
            default: "Tab",
            comment: "Display label for Tab key in hotkey recorder"
        ),
        CGKeyCode(kVK_Space): localized(
            "settings.keyboard.keyLabel.space",
            default: "Space",
            comment: "Display label for Space key in hotkey recorder"
        ),
        CGKeyCode(kVK_Delete): localized(
            "settings.keyboard.keyLabel.delete",
            default: "Delete",
            comment: "Display label for Delete key in hotkey recorder"
        ),
        CGKeyCode(kVK_Escape): localized(
            "settings.keyboard.keyLabel.escape",
            default: "Esc",
            comment: "Display label for Escape key in hotkey recorder"
        ),
        CGKeyCode(kVK_ForwardDelete): localized(
            "settings.keyboard.keyLabel.forwardDelete",
            default: "Del",
            comment: "Display label for Forward Delete key in hotkey recorder"
        ),
        CGKeyCode(kVK_LeftArrow): localized(
            "settings.keyboard.keyLabel.left",
            default: "Left",
            comment: "Display label for left arrow key in hotkey recorder"
        ),
        CGKeyCode(kVK_RightArrow): localized(
            "settings.keyboard.keyLabel.right",
            default: "Right",
            comment: "Display label for right arrow key in hotkey recorder"
        ),
        CGKeyCode(kVK_DownArrow): localized(
            "settings.keyboard.keyLabel.down",
            default: "Down",
            comment: "Display label for down arrow key in hotkey recorder"
        ),
        CGKeyCode(kVK_UpArrow): localized(
            "settings.keyboard.keyLabel.up",
            default: "Up",
            comment: "Display label for up arrow key in hotkey recorder"
        ),
    ]
}
