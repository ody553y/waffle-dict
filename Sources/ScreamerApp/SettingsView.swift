import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            ModelsSettingsView()
                .tabItem { Label("Models", systemImage: "arrow.down.circle") }
            KeyboardSettingsView()
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 320)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("pasteAfterTranscription") private var pasteAfterTranscription = true
    @AppStorage("clipboardFallback") private var clipboardFallback = true

    var body: some View {
        Form {
            Toggle("Paste into active app after transcription", isOn: $pasteAfterTranscription)
            Toggle("Copy to clipboard as fallback", isOn: $clipboardFallback)
        }
        .padding()
    }
}

struct ModelsSettingsView: View {
    var body: some View {
        VStack {
            Text("Model management coming soon.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct KeyboardSettingsView: View {
    var body: some View {
        VStack {
            Text("Global hotkey configuration coming soon.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
