import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SharedSettingsStore()
    lazy var keyboardController = KeyboardDeleteController(settings: settings)
    lazy var finderContextMenuFallbackController = FinderContextMenuFallbackController(settings: settings)
    lazy var finderServiceProvider = FinderServiceProvider(settings: settings)
    private lazy var settingsWindowController = SettingsWindowController(
        settings: settings,
        keyboardController: keyboardController
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
        statusMenuController?.keyboardStatusTitle = { [weak self] in
            self?.keyboardController.isRunning == true
                ? "Backspace Keyboard Tap: Running"
                : "Backspace Keyboard Tap: Stopped"
        }
        statusMenuController?.refreshControllers = { [weak self] in
            self?.keyboardController.refresh()
            self?.finderContextMenuFallbackController.refresh()
        }

        keyboardController.refresh()
        finderContextMenuFallbackController.refresh()
        startPermissionRefreshTimer()
        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.keyboardController.refresh()
                    self?.finderContextMenuFallbackController.refresh()
                    self?.statusMenuController?.rebuildMenu()
                }
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionRefreshTimer?.invalidate()
        keyboardController.stop()
        finderContextMenuFallbackController.stop()
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController.show()
    }

    private func startPermissionRefreshTimer() {
        lastPermissionState = currentPermissionState()
        permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.keyboardController.refresh()
            self.finderContextMenuFallbackController.refresh()

            let permissionState = self.currentPermissionState()
            if permissionState != self.lastPermissionState {
                self.lastPermissionState = permissionState
                self.statusMenuController?.rebuildMenu()
            }
        }
    }

    private func currentPermissionState() -> PermissionState {
        PermissionState(
            accessibility: KeyboardDeleteController.isAccessibilityTrusted,
            inputMonitoring: KeyboardDeleteController.canListenToInputEvents,
            keyboardTapRunning: keyboardController.isRunning
        )
    }
}

private struct PermissionState: Equatable {
    let accessibility: Bool
    let inputMonitoring: Bool
    let keyboardTapRunning: Bool
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
