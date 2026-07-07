import AppKit
import Combine
import FinderSync
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SharedSettingsStore()
    lazy var controllers = TweakControllers(settings: settings)
    lazy var finderServiceProvider = FinderServiceProvider(settings: settings)
    private lazy var settingsWindowController = SettingsWindowController(
        settings: settings,
        keyboardController: controllers.keyboard
    )

    private var statusMenuController: StatusMenuController?
    private var cancellables = Set<AnyCancellable>()
    private var permissionRefreshTimer: Timer?
    private var lastPermissionState: PermissionState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.servicesProvider = finderServiceProvider
        NSUpdateDynamicServices()
        statusMenuController = StatusMenuController(settings: settings)
        statusMenuController?.showSettings = { [weak self] in self?.showSettings() }

        controllers.refreshAll()
        startPermissionRefreshTimer()
        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.controllers.refreshAll()
                    self?.statusMenuController?.rebuildMenu()
                }
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionRefreshTimer?.invalidate()
        controllers.stopAll()
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController.show()
    }

    private func startPermissionRefreshTimer() {
        lastPermissionState = currentPermissionState()
        permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.controllers.refreshAll()

            let permissionState = self.currentPermissionState()
            if permissionState != self.lastPermissionState {
                self.lastPermissionState = permissionState
                self.statusMenuController?.rebuildMenu()
            }
        }
    }

    private func currentPermissionState() -> PermissionState {
        PermissionState(
            accessibility: Permissions.isAccessibilityTrusted,
            inputMonitoring: Permissions.canListenToInputEvents,
            finderExtensionEnabled: FIFinderSyncController.isExtensionEnabled
        )
    }
}

// Drives the status-menu rebuild: the menu's status line reflects these, so a
// change to any of them (granted a permission, enabled the extension) refreshes
// the menu on the next poll.
private struct PermissionState: Equatable {
    let accessibility: Bool
    let inputMonitoring: Bool
    let finderExtensionEnabled: Bool
}

private final class SettingsWindowController {
    private let settings: SharedSettingsStore
    private let keyboardController: KeyboardDeleteController
    private var window: NSWindow?

    init(settings: SharedSettingsStore, keyboardController: KeyboardDeleteController) {
        self.settings = settings
        self.keyboardController = keyboardController
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let rootView = SettingsView(settings: settings, keyboardController: keyboardController)
            .frame(minWidth: 820, minHeight: 620)

        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = "Mac Tweaks Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 800, height: 600)
        window.setFrameAutosaveName("MacTweaksSettingsWindow")
        window.center()
        return window
    }
}
