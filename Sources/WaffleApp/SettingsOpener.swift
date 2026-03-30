import AppKit

@MainActor
enum SettingsOpener {
    static func open(
        openSettings: () -> Void,
        activate: (Bool) -> Void = { NSApplication.shared.activate(ignoringOtherApps: $0) },
        sendAction: (Selector, AnyObject?, AnyObject?) -> Bool = { action, target, sender in
            NSApplication.shared.sendAction(action, to: target, from: sender)
        }
    ) {
        activate(true)

        let didOpenWithAppKit = sendAction(Selector(("showSettingsWindow:")), nil, nil)
        if didOpenWithAppKit == false {
            openSettings()
        }

        activate(true)
    }
}
