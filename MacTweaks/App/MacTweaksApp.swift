import SwiftUI

@main
struct MacTweaksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: appDelegate.settings, keyboardController: appDelegate.keyboardController)
                .frame(minWidth: 820, minHeight: 620)
        }
    }
}
