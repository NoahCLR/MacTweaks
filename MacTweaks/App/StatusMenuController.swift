import AppKit
import FinderSync

final class StatusMenuController: NSObject, NSMenuDelegate {
    /// Opens the Settings window; a non-nil tab jumps straight to it (the status
    /// row targets Permissions), nil keeps whatever tab was last selected.
    var showSettings: ((SettingsTab?) -> Void)?

    private let settings: SharedSettingsStore
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    init(settings: SharedSettingsStore) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // One long-lived menu, repopulated in menuNeedsUpdate just before every
        // open — so the items (toggle states, the OCR shortcut in its title) can
        // never show stale state, no matter when settings last changed.
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    func rebuildMenu() {
        updateStatusItemAppearance()
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(toggleMenuItem(
            title: "Enable Mac Tweaks",
            action: #selector(toggleMasterEnabled),
            state: settings.masterEnabled
        ))
        menu.addItem(statusSummaryItem())
        menu.addItem(.separator())

        menu.addItem(finderTweaksMenuItem())
        menu.addItem(clipboardTweaksMenuItem())

        menu.addItem(.separator())
        // Both bottom items carry an explicit icon: macOS auto-decorates
        // "Settings..." with a gear, which shifts icon-less siblings into the
        // icon-alignment column and makes Quit look indented. Giving Quit its own
        // symbol keeps the two rows aligned deliberately on every OS version.
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Mac Tweaks", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Mac Tweaks")
        button.imagePosition = .imageOnly
        button.toolTip = currentStatus().title
    }

    // Menu-bar surfaces quick toggles only. Reordering actions, choosing default
    // apps, and granting permissions live in Settings (the "Settings..." item).
    //
    // Grouping is by what the tweak is about, not how it's delivered: Finder
    // Tweaks changes how you work with files in Finder (right-click actions and
    // the Finder-only keystrokes), Clipboard Tweaks is about clipboard content
    // (materializing it as a file, filling it via OCR).
    private func finderTweaksMenuItem() -> NSMenuItem {
        submenuItem(title: "Finder Tweaks") { submenu in
            let snapshot = settings.currentSnapshot

            submenu.addItem(.sectionHeader(title: "Right-Click Actions"))
            // Follow the user's configured menu order (Settings → Finder Tweaks →
            // Menu Order), the same array that drives the real Finder right-click menu.
            for action in settings.finderActionOrder {
                submenu.addItem(finderActionToggleItem(action, snapshot: snapshot))
            }

            // The fallback toggle sits under the same header: it controls where
            // those right-click actions appear, not a separate tweak.
            let fallbackItem = toggleMenuItem(
                title: "Fallback Menu (⌥-Right-Click)",
                action: #selector(toggleEnhancedFinderMenus),
                state: settings.enhancedFinderMenusEnabled
            )
            fallbackItem.toolTip = "Shows Mac Tweaks actions on Option-right-click where the native Finder menu isn't available (e.g. the Desktop and cloud folders)."
            submenu.addItem(fallbackItem)
            submenu.addItem(.separator())

            submenu.addItem(.sectionHeader(title: "Keyboard"))
            submenu.addItem(toggleMenuItem(
                title: "Backspace Deletes Files",
                action: #selector(toggleDeleteKey),
                state: settings.deleteKeyEnabled
            ))
            submenu.addItem(toggleMenuItem(
                title: "Cut & Paste Files (⌘X / ⌘V)",
                action: #selector(toggleCutFiles),
                state: settings.cutFilesEnabled
            ))
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

    private func clipboardTweaksMenuItem() -> NSMenuItem {
        submenuItem(title: "Clipboard Tweaks") { submenu in
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
            submenu.addItem(.separator())
            let ocrItem = toggleMenuItem(
                title: "OCR to Clipboard (\(settings.ocrHotKey.displayString))",
                action: #selector(toggleOCR),
                state: settings.ocrEnabled
            )
            ocrItem.toolTip = "Press the shortcut, drag to select part of the screen, and its text is copied to the clipboard. Change the shortcut in Settings."
            submenu.addItem(ocrItem)
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
    /// clickable and jumps straight to the Permissions tab; otherwise it's an
    /// informational row. The explicit icon doubles as an override for the gear
    /// macOS would otherwise auto-attach to a Settings-opening item.
    private func statusSummaryItem() -> NSMenuItem {
        let status = currentStatus()
        guard status.needsAttention else {
            return disabledItem(status.title)
        }

        let item = NSMenuItem(title: status.title, action: #selector(openPermissions), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: status.title)
        item.toolTip = "Open the Permissions tab to resolve."
        return item
    }

    private func currentStatus() -> StatusSummary {
        guard settings.masterEnabled else { return .paused }
        if !FIFinderSyncController.isExtensionEnabled { return .needsFinderExtension }
        if !Permissions.isAccessibilityTrusted { return .permissionsNeeded }
        if settings.ocrEnabled && !Permissions.canCaptureScreen { return .permissionsNeeded }
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

    @objc private func toggleOCR() {
        settings.ocrEnabled.toggle()
        rebuildMenu()
    }

    @objc private func openSettings() {
        showSettings?(nil)
    }

    @objc private func openPermissions() {
        showSettings?(.permissions)
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

    /// Icon for the clickable attention states (never shown for the others).
    var symbolName: String {
        switch self {
        case .needsFinderExtension:
            return "puzzlepiece.extension"
        case .paused, .permissionsNeeded, .ready:
            return "lock.shield"
        }
    }
}
