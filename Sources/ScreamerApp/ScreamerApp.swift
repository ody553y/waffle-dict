import SwiftUI

@main
struct ScreamerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Screamer", systemImage: "mic.fill") {
            MenuBarView(
                dictationController: appDelegate.dictationController,
                modelStore: appDelegate.modelStore
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                hotkeyDisplayValue: appDelegate.hotkeyDisplayValue,
                modelStore: appDelegate.modelStore
            )
        }
    }
}
