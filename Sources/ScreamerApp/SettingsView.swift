import AppKit
import Carbon.HIToolbox
import SwiftUI
import ScreamerCore

struct SettingsView: View {
    let onUpdateHotkey: (GlobalHotkey) -> Void
    let onLMStudioConfigurationChanged: () -> Void
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
            AISettingsView(onConfigurationChanged: onLMStudioConfigurationChanged)
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
    @AppStorage("pasteIntoActiveApp") private var pasteIntoActiveApp = true
    @AppStorage("copyToClipboardAsFallback") private var copyToClipboardAsFallback = true
    @AppStorage("showPreviewAfterDictation")
    private var showPreviewAfterDictation = true
    @AppStorage("previewAutoDismissSeconds")
    private var previewAutoDismissSeconds = 10
    @AppStorage("languageHint")
    private var languageHint = ""

    @ObservedObject var modelStore: ModelStore
    @ObservedObject var updaterSettings: UpdaterSettings
    private let debugInfoDefaultsKey = "showDebugInfo"

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
                            default: "Parakeet supports English only. Screamer will send \"en\" while Parakeet is selected.",
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
                            default: "Enable with terminal: defaults write com.screamer.app showDebugInfo -bool true",
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
    @AppStorage("lmStudioHost") private var lmStudioHost = "127.0.0.1"
    @AppStorage("lmStudioPort") private var lmStudioPort = "1234"
    @AppStorage("lmStudioModelID") private var lmStudioModelID = ""
    @AppStorage("lmStudioStreaming") private var lmStudioStreaming = true
    @AppStorage("lmStudioDefaultTranslationLanguage")
    private var lmStudioDefaultTranslationLanguage = AppLanguageOption.defaultCode

    let onConfigurationChanged: () -> Void

    @State private var availableModels: [LMStudioModel] = []
    @State private var isConnected = false
    @State private var connectionMessage = localized(
        "settings.ai.connection.notConnected",
        default: "Not connected",
        comment: "Default LM Studio connection status text"
    )
    @State private var isTestingConnection = false

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
        }
        .padding()
        .task {
            await refreshModels()
        }
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
