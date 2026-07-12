import SwiftUI

@main
struct MacTweaksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // The standard ⌘, Settings scene has no external tab-steering (only the
    // status menu's attention row does that, via the app-owned window), so it
    // gets a router nobody writes to.
    @StateObject private var router = SettingsRouter()

    var body: some Scene {
        Settings {
            SettingsView(
                settings: appDelegate.settings,
                router: router,
                permissionOnboarding: appDelegate.permissionOnboarding,
                keyboardController: appDelegate.controllers.keyboard,
                ocrController: appDelegate.controllers.screenOCR
            )
            .frame(minWidth: 820, minHeight: 620)
        }
    }
}
