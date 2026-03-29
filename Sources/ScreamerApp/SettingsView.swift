import AppKit
import Carbon.HIToolbox
import SwiftUI
import ScreamerCore

struct SettingsView: View {
    let onUpdateHotkey: (GlobalHotkey) -> Void
    @ObservedObject var modelStore: ModelStore

    var body: some View {
        TabView {
            GeneralSettingsView(modelStore: modelStore)
                .tabItem { Label("General", systemImage: "gear") }
            ModelsSettingsView(modelStore: modelStore)
                .tabItem { Label("Models", systemImage: "arrow.down.circle") }
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
                    ForEach(Self.languageOptions, id: \.code) { option in
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
        }
        .padding()
        .task {
            modelStore.refreshCatalog()
        }
    }

    private var isParakeetSelected: Bool {
        modelStore.selectedEntry?.family == .parakeet
    }

    private struct LanguageOption {
        let name: String
        let code: String
    }

    private static let languageOptions: [LanguageOption] = [
        LanguageOption(name: "English", code: "en"),
        LanguageOption(name: "Spanish", code: "es"),
        LanguageOption(name: "French", code: "fr"),
        LanguageOption(name: "German", code: "de"),
        LanguageOption(name: "Italian", code: "it"),
        LanguageOption(name: "Portuguese", code: "pt"),
        LanguageOption(name: "Chinese", code: "zh"),
        LanguageOption(name: "Japanese", code: "ja"),
        LanguageOption(name: "Korean", code: "ko"),
        LanguageOption(name: "Russian", code: "ru"),
        LanguageOption(name: "Arabic", code: "ar"),
        LanguageOption(name: "Hindi", code: "hi"),
    ]
}

struct ModelsSettingsView: View {
    @ObservedObject var modelStore: ModelStore

    var body: some View {
        List(modelStore.catalog) { entry in
            ModelRowView(entry: entry, modelStore: modelStore)
        }
        .task {
            modelStore.refreshCatalog()
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
