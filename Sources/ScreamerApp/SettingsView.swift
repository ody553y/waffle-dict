import SwiftUI
import ScreamerCore

struct SettingsView: View {
    let hotkeyDisplayValue: String
    @ObservedObject var modelStore: ModelStore

    var body: some View {
        TabView {
            GeneralSettingsView(modelStore: modelStore)
                .tabItem { Label("General", systemImage: "gear") }
            ModelsSettingsView(modelStore: modelStore)
                .tabItem { Label("Models", systemImage: "arrow.down.circle") }
            KeyboardSettingsView(hotkeyDisplayValue: hotkeyDisplayValue)
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
        }
        .padding()
        .task {
            modelStore.refreshCatalog()
        }
    }
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
    let hotkeyDisplayValue: String

    var body: some View {
        Form {
            LabeledContent("Global Hotkey") {
                Text(hotkeyDisplayValue)
                    .font(.system(.body, design: .monospaced))
            }
            Button("Change…") {
                // Placeholder for future hotkey picker support.
            }
            .disabled(true)
            Text("Custom hotkey selection is coming soon.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
