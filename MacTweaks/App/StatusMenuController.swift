import AppKit
import FinderSync

final class StatusMenuController: NSObject {
    var showSettings: (() -> Void)?

    private let settings: SharedSettingsStore
    private let statusItem: NSStatusItem

    init(settings: SharedSettingsStore) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        rebuildMenu()
    }

    func rebuildMenu() {
        updateStatusItemAppearance()

        let menu = NSMenu()
        menu.addItem(toggleMenuItem(
            title: "Enable Mac Tweaks",
            action: #selector(toggleMasterEnabled),
            state: settings.masterEnabled
        ))
        menu.addItem(statusSummaryItem())
        menu.addItem(.separator())

        menu.addItem(finderActionsMenuItem())
        menu.addItem(keyboardMenuItem())

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Mac Tweaks", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Mac Tweaks")
        button.imagePosition = .imageOnly
        button.toolTip = currentStatus().title
    }

    // Menu-bar surfaces quick toggles only. Reordering actions, choosing default
    // apps, and granting permissions live in Settings (the "Settings..." item).
    private func finderActionsMenuItem() -> NSMenuItem {
        submenuItem(title: "Finder Actions") { submenu in
            let snapshot = settings.currentSnapshot

            // Follow the user's configured menu order (Settings → Finder Actions →
            // Menu Order), the same array that drives the real Finder right-click menu.
            for action in settings.finderActionOrder {
                submenu.addItem(finderActionToggleItem(action, snapshot: snapshot))
            }
            submenu.addItem(.separator())

            let fallbackItem = toggleMenuItem(
                title: "Fallback Menu (⌥-Right-Click)",
                action: #selector(toggleEnhancedFinderMenus),
                state: settings.enhancedFinderMenusEnabled
            )
            fallbackItem.toolTip = "Shows Mac Tweaks actions on Option-right-click where the native Finder menu isn't available (e.g. the Desktop and cloud folders)."
            submenu.addItem(fallbackItem)
        }
    }

    private func finderActionToggleItem(_ action: FinderMenuAction, snapshot: SettingsSnapshot) -> NSMenuItem {
        switch action {
        case .createNewFileHere:
            return toggleMenuItem(
                title: "Create New File",
                action: #selector(toggleCreateFile),
                state: settings.createFileEnabled
            )
        case .openInIDE:
            return toggleMenuItem(
                title: FinderMenuAction.openInIDE.title(settings: snapshot),
                action: #selector(toggleOpenInIDE),
                state: settings.openInIDEEnabled
            )
        case .copyPath:
            return toggleMenuItem(
                title: "Copy Path",
                action: #selector(toggleCopyPath),
                state: settings.copyPathEnabled
            )
        case .openTerminalHere:
            return toggleMenuItem(
                title: FinderMenuAction.openTerminalHere.title(settings: snapshot),
                action: #selector(toggleOpenTerminal),
                state: settings.openTerminalEnabled
            )
        }
    }

    private func keyboardMenuItem() -> NSMenuItem {
        submenuItem(title: "Keyboard") { submenu in
            submenu.addItem(toggleMenuItem(
                title: "Backspace Deletes Files",
                action: #selector(toggleDeleteKey),
                state: settings.deleteKeyEnabled
            ))
            submenu.addItem(.separator())
            submenu.addItem(toggleMenuItem(
                title: "Cut & Paste Files (⌘X / ⌘V)",
                action: #selector(toggleCutFiles),
                state: settings.cutFilesEnabled
            ))
            submenu.addItem(.separator())
            submenu.addItem(toggleMenuItem(
                title: "Paste Clipboard as File",
                action: #selector(toggleClipboardToFile),
                state: settings.clipboardToFileEnabled
            ))
            if settings.clipboardToFileEnabled {
                submenu.addItem(subToggleMenuItem(
                    title: "Images",
                    action: #selector(togglePasteImageAsFile),
                    state: settings.pasteImageAsFile
                ))
                submenu.addItem(subToggleMenuItem(
                    title: "Text",
                    action: #selector(togglePasteTextAsFile),
                    state: settings.pasteTextAsFile
                ))
            }
        }
    }

    private func toggleMenuItem(title: String, action: Selector, state: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = state ? .on : .off
        return item
    }

    /// A toggle rendered as a sub-option (indented) of the row above it.
    private func subToggleMenuItem(title: String, action: Selector, state: Bool) -> NSMenuItem {
        let item = toggleMenuItem(title: title, action: action, state: state)
        item.indentationLevel = 1
        return item
    }

    private func submenuItem(title: String, build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        build(submenu)
        item.submenu = submenu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// The status line. When something needs the user to act (a missing Finder
    /// extension or permission — both now resolved in Settings), the line becomes
    /// clickable and opens Settings; otherwise it's an informational row.
    private func statusSummaryItem() -> NSMenuItem {
        let status = currentStatus()
        guard status.needsAttention else {
            return disabledItem(status.title)
        }

        let item = NSMenuItem(title: status.title, action: #selector(openSettings), keyEquivalent: "")
        item.target = self
        item.toolTip = "Open Settings to resolve."
        return item
    }

    private func currentStatus() -> StatusSummary {
        guard settings.masterEnabled else { return .paused }
        if !FIFinderSyncController.isExtensionEnabled { return .needsFinderExtension }
        if !Permissions.isAccessibilityTrusted || !Permissions.canListenToInputEvents { return .permissionsNeeded }
        return .ready
    }

    @objc private func toggleMasterEnabled() {
        settings.masterEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleCreateFile() {
        settings.createFileEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleOpenInIDE() {
        settings.openInIDEEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleCopyPath() {
        settings.copyPathEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleOpenTerminal() {
        settings.openTerminalEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleEnhancedFinderMenus() {
        settings.enhancedFinderMenusEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleDeleteKey() {
        settings.deleteKeyEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleCutFiles() {
        settings.cutFilesEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleClipboardToFile() {
        settings.clipboardToFileEnabled.toggle()
        rebuildMenu()
    }

    @objc private func togglePasteImageAsFile() {
        settings.pasteImageAsFile.toggle()
        rebuildMenu()
    }

    @objc private func togglePasteTextAsFile() {
        settings.pasteTextAsFile.toggle()
        rebuildMenu()
    }

    @objc private func openSettings() {
        showSettings?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private enum StatusSummary {
    case paused
    case needsFinderExtension
    case permissionsNeeded
    case ready

    var title: String {
        switch self {
        case .paused:
            return "Paused"
        case .needsFinderExtension:
            return "Needs Finder Extension"
        case .permissionsNeeded:
            return "Some permissions needed"
        case .ready:
            return "Ready"
        }
    }

    /// Whether the user must act (in Settings) to reach a working state.
    var needsAttention: Bool {
        switch self {
        case .needsFinderExtension, .permissionsNeeded:
            return true
        case .paused, .ready:
            return false
        }
    }
}
