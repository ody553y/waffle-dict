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
                .tabItem { Label("General", systemImage: "gear") }
            ModelsSettingsView(modelStore: modelStore)
                .tabItem { Label("Models", systemImage: "arrow.down.circle") }
            AISettingsView(onConfigurationChanged: onLMStudioConfigurationChanged)
                .tabItem { Label("AI", systemImage: "sparkles") }
            KeyboardSettingsView(onUpdateHotkey: onUpdateHotkey)
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
        }
        .frame(width: 540, height: 360)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("pasteIntoActiveApp") private var pasteIntoActiveApp = true
    @AppStorage("copyToClipboardAsFallback") private var copyToClipboardAsFallback = true
    @AppStorage("showTranscriptInMenuAfterTranscription")
    private var showTranscriptInMenuAfterTranscription = true
    @AppStorage("languageHint")
    private var languageHint = ""

    @ObservedObject var modelStore: ModelStore
    @ObservedObject var updaterSettings: UpdaterSettings
    private let debugInfoDefaultsKey = "showDebugInfo"

    var body: some View {
        Form {
            Toggle("Paste into active app after transcription", isOn: $pasteIntoActiveApp)
            Toggle("Copy to clipboard as fallback", isOn: $copyToClipboardAsFallback)
            Toggle(
                "Show transcript in menu after transcription",
                isOn: $showTranscriptInMenuAfterTranscription
            )

            Section("Transcription Model") {
                if modelStore.installedEntries.isEmpty {
                    Text("No installed models yet. Open the Models tab to download one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "Transcription Model",
                        selection: Binding(
                            get: { modelStore.resolvedSelectedModelID ?? "" },
                            set: { modelStore.setSelectedModelID($0) }
                        )
                    ) {
                        ForEach(modelStore.installedEntries) { entry in
                            Text(entry.displayName).tag(entry.id)
                        }
                    }
                    Text("The next transcription will use the selected installed model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Language Hint") {
                Picker("Language", selection: $languageHint) {
                    Text("Auto-detect").tag("")
                    ForEach(AppLanguageOption.all) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .disabled(isParakeetSelected)

                if isParakeetSelected {
                    Text("Parakeet supports English only. Screamer will send \"en\" while Parakeet is selected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Auto-detect sends no language hint. Selecting a language sends its ISO 639-1 code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if shouldShowDebugSection {
                Section("Debug") {
                    LabeledContent("Startup") {
                        Text(metricValue(for: "app.startup"))
                    }

                    LabeledContent("Transcription Avg") {
                        Text(combinedMetricValue(for: ["dictation.transcription.e2e", "file.transcription.e2e"]))
                    }

                    LabeledContent("Worker Health") {
                        Text(metricValue(for: "worker.health.check"))
                    }

                    LabeledContent("DB Save") {
                        Text(metricValue(for: "db.save"))
                    }

                    LabeledContent("DB Fetch All") {
                        Text(metricValue(for: "db.fetchAll"))
                    }

                    LabeledContent("DB Search") {
                        Text(metricValue(for: "db.search"))
                    }

                    Button("Copy Report") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(PerformanceMetrics.shared.report(), forType: .string)
                    }

                    Text("Enable with terminal: defaults write com.screamer.app showDebugInfo -bool true")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Updates") {
                Toggle(
                    "Check for updates automatically",
                    isOn: Binding(
                        get: { updaterSettings.automaticallyChecksForUpdates },
                        set: { updaterSettings.setAutomaticallyChecksForUpdates($0) }
                    )
                )
                .disabled(updaterSettings.isUpdaterReady == false)

                HStack {
                    Text("Current Version")
                    Spacer()
                    Text(updaterSettings.currentVersion)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Last Check")
                    Spacer()
                    Text(updaterSettings.lastUpdateCheckDescription)
                        .foregroundStyle(.secondary)
                }

                Button("Check Now") {
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
            return "No samples"
        }
        return "\(formatMilliseconds(summary.meanDurationSeconds)) avg (\(summary.sampleCount)x)"
    }

    private func combinedMetricValue(for labels: [String]) -> String {
        let summaries = labels.compactMap { PerformanceMetrics.shared.summary(for: $0) }
        guard summaries.isEmpty == false else {
            return "No samples"
        }

        let sampleCount = summaries.reduce(0) { $0 + $1.sampleCount }
        guard sampleCount > 0 else {
            return "No samples"
        }

        let totalDurationSeconds = summaries.reduce(0.0) { $0 + $1.totalDurationSeconds }
        let meanDurationSeconds = totalDurationSeconds / Double(sampleCount)
        return "\(formatMilliseconds(meanDurationSeconds)) avg (\(sampleCount)x)"
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
                Button("Refresh") {
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
    @State private var connectionMessage = "Not connected"
    @State private var isTestingConnection = false

    var body: some View {
        Form {
            Section("LM Studio Connection") {
                TextField("Host", text: $lmStudioHost)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: lmStudioHost) { _, _ in
                        onConfigurationChanged()
                    }

                TextField("Port", text: $lmStudioPort)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: lmStudioPort) { _, _ in
                        onConfigurationChanged()
                    }

                HStack(spacing: 8) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(isConnected ? "Connected" : "Not connected")
                        .font(.caption)
                    Spacer()
                }

                if connectionMessage.isEmpty == false {
                    Text(connectionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Test Connection") {
                    Task {
                        await refreshModels()
                    }
                }
                .disabled(isTestingConnection)
            }

            Section("Default Model") {
                Picker("Model", selection: $lmStudioModelID) {
                    if availableModels.isEmpty {
                        Text("No models loaded").tag("")
                    } else {
                        ForEach(availableModels, id: \.id) { model in
                            Text(model.id).tag(model.id)
                        }
                    }
                }
                .disabled(availableModels.isEmpty)

                Button("Refresh") {
                    Task {
                        await refreshModels()
                    }
                }
                .disabled(isTestingConnection)

                Text("Models are managed in LM Studio. Load a model there to use it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Defaults") {
                Toggle("Use streaming responses", isOn: $lmStudioStreaming)

                Picker("Default translation language", selection: $lmStudioDefaultTranslationLanguage) {
                    ForEach(AppLanguageOption.all) { option in
                        Text(option.name).tag(option.code)
                    }
                }

                Text("Speaker identification requires a HuggingFace token configured in the worker.")
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
            connectionMessage = "Enter a host to connect."
            availableModels = []
            return
        }

        guard let port = Int(lmStudioPort), port > 0 else {
            isConnected = false
            connectionMessage = "Port must be a valid number."
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
            connectionMessage = "Connection successful."

            if models.contains(where: { $0.id == lmStudioModelID }) == false {
                lmStudioModelID = models.first?.id ?? ""
            }
        } catch LMStudioClientError.noModelsLoaded {
            availableModels = []
            isConnected = true
            connectionMessage = "Connected, but no models are loaded in LM Studio."
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
            return "LM Studio is not running or unreachable."
        case LMStudioClientError.unexpectedStatusCode(let code):
            return "LM Studio returned status code \(code)."
        default:
            return "Connection test failed."
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
                        Text("In Use")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }

                    if modelStore.isInstalled(entry) {
                        Text("Installed")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    } else if entry.available == false {
                        Text("Coming Soon")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }

                Text("\(entry.sizeMB) MB • \(entry.languageCount) language\(entry.languageCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if modelStore.activeDownloadID == entry.id {
                    ProgressView(value: modelStore.progress(for: entry.id))
                        .frame(maxWidth: 180)
                }

                if let errorMessage = modelStore.errorMessage(for: entry.id) {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            if modelStore.isInstalled(entry) {
                Button("Remove") {
                    modelStore.removeInstalledModel(id: entry.id)
                }
                .buttonStyle(.bordered)
            } else {
                Button(entry.available ? "Download" : "Unavailable") {
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

            Button("Reset to Default") {
                save(hotkey: .optionSpace)
            }
            .buttonStyle(.bordered)

            Text("Shortcuts must include at least one modifier key. Avoid common Spotlight shortcuts like ⌘Space.")
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
            validationMessage = "Could not save this shortcut."
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
        AppLanguageOption(name: "English", code: "en"),
        AppLanguageOption(name: "Spanish", code: "es"),
        AppLanguageOption(name: "French", code: "fr"),
        AppLanguageOption(name: "German", code: "de"),
        AppLanguageOption(name: "Italian", code: "it"),
        AppLanguageOption(name: "Portuguese", code: "pt"),
        AppLanguageOption(name: "Chinese", code: "zh"),
        AppLanguageOption(name: "Japanese", code: "ja"),
        AppLanguageOption(name: "Korean", code: "ko"),
        AppLanguageOption(name: "Russian", code: "ru"),
        AppLanguageOption(name: "Arabic", code: "ar"),
        AppLanguageOption(name: "Hindi", code: "hi"),
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
            LabeledContent("Global Hotkey") {
                Text(currentHotkey.displayValue)
                    .font(.system(.body, design: .monospaced))
            }

            HStack(spacing: 12) {
                Button(isRecording ? "Press your shortcut…" : "Change…") {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
                .buttonStyle(.borderedProminent)

                if isRecording {
                    Text("Press your shortcut…")
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
            setValidationMessage("Shortcut must include at least one modifier (⌘, ⌥, ⌃, ⇧).")
            return
        }

        if conflictsWithSystemShortcut(keyCode: keyCode, modifiers: modifiers) {
            setValidationMessage("That shortcut likely conflicts with a system shortcut. Try a different combo.")
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

        return "Key\(keyCode)"
    }

    private static let keyLabelMap: [CGKeyCode: String] = [
        CGKeyCode(kVK_Return): "Return",
        CGKeyCode(kVK_Tab): "Tab",
        CGKeyCode(kVK_Space): "Space",
        CGKeyCode(kVK_Delete): "Delete",
        CGKeyCode(kVK_Escape): "Esc",
        CGKeyCode(kVK_ForwardDelete): "Del",
        CGKeyCode(kVK_LeftArrow): "Left",
        CGKeyCode(kVK_RightArrow): "Right",
        CGKeyCode(kVK_DownArrow): "Down",
        CGKeyCode(kVK_UpArrow): "Up",
    ]
}
