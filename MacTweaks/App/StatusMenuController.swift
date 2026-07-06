import AppKit
import FinderSync

final class StatusMenuController: NSObject {
    var showSettings: (() -> Void)?
    var refreshControllers: (() -> Void)?
    var keyboardStatusTitle: (() -> String)?

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
            state: settings.masterEnabled,
            toolTip: "Turns every Mac Tweaks Finder and keyboard feature on or off."
        ))
        menu.addItem(disabledItem(statusSummaryTitle(), toolTip: "Current Mac Tweaks status."))
        menu.addItem(.separator())

        menu.addItem(finderActionsMenuItem())
        menu.addItem(defaultAppsMenuItem())
        menu.addItem(keyboardMenuItem())
        menu.addItem(permissionsMenuItem())

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.toolTip = "Open the Mac Tweaks Settings window."
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Mac Tweaks", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.toolTip = "Quit the menu bar app."
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Mac Tweaks")
        button.imagePosition = .imageOnly
        button.toolTip = statusSummaryTitle()
    }

    private func finderActionsMenuItem() -> NSMenuItem {
        submenuItem(title: "Finder Actions", toolTip: "Configure the actions shown in Finder right-click menus.") { submenu in
            let snapshot = settings.currentSnapshot

            submenu.addItem(toggleMenuItem(
                title: "Create New File",
                action: #selector(toggleCreateFile),
                state: settings.createFileEnabled,
                toolTip: "Adds a blank file in the current Finder folder."
            ))
            submenu.addItem(toggleMenuItem(
                title: FinderMenuAction.openInIDE.title(settings: snapshot),
                action: #selector(toggleOpenInIDE),
                state: settings.openInIDEEnabled,
                toolTip: "Opens the selected Finder item with the configured IDE."
            ))
            submenu.addItem(toggleMenuItem(
                title: "Copy Path",
                action: #selector(toggleCopyPath),
                state: settings.copyPathEnabled,
                toolTip: "Copies selected Finder item paths to the clipboard."
            ))
            submenu.addItem(toggleMenuItem(
                title: FinderMenuAction.openTerminalHere.title(settings: snapshot),
                action: #selector(toggleOpenTerminal),
                state: settings.openTerminalEnabled,
                toolTip: "Opens the selected Finder folder with the configured terminal."
            ))
            submenu.addItem(.separator())
            submenu.addItem(toggleMenuItem(
                title: "Option-click Menu",
                action: #selector(toggleEnhancedFinderMenus),
                state: settings.enhancedFinderMenusEnabled,
                toolTip: "Shows the fallback Mac Tweaks menu with Option-right-click in Finder locations where extensions are unreliable."
            ))
            submenu.addItem(toggleMenuItem(
                title: "Open Parent for Files",
                action: #selector(toggleOpenContainingFolderForFiles),
                state: settings.openContainingFolderForFiles,
                toolTip: "Targets the containing folder when a file is selected for IDE or terminal actions."
            ))
            submenu.addItem(.separator())
            submenu.addItem(finderActionOrderMenuItem())
        }
    }

    private func defaultAppsMenuItem() -> NSMenuItem {
        submenuItem(title: "Default Apps", toolTip: "Choose the apps used by Finder actions.") { submenu in
            let ideTitle = settings.ideApplicationURL?.deletingPathExtension().lastPathComponent ?? "Not Selected"
            submenu.addItem(disabledItem("IDE: \(shortMenuTitle(ideTitle, maxLength: 24))", toolTip: "Current IDE: \(ideTitle)"))
            let chooseIDEItem = NSMenuItem(title: "Choose IDE...", action: #selector(chooseIDE), keyEquivalent: "")
            chooseIDEItem.target = self
            chooseIDEItem.toolTip = "Choose the app used by Open in IDE."
            submenu.addItem(chooseIDEItem)

            submenu.addItem(.separator())

            let terminalTitle = settings.terminalApplicationURL?.deletingPathExtension().lastPathComponent ?? "Not Selected"
            submenu.addItem(disabledItem("Terminal: \(shortMenuTitle(terminalTitle, maxLength: 19))", toolTip: "Current terminal: \(terminalTitle)"))
            let chooseTerminalItem = NSMenuItem(title: "Choose Terminal...", action: #selector(chooseTerminal), keyEquivalent: "")
            chooseTerminalItem.target = self
            chooseTerminalItem.toolTip = "Choose the app used by Open Terminal."
            submenu.addItem(chooseTerminalItem)
        }
    }

    private func keyboardMenuItem() -> NSMenuItem {
        submenuItem(title: "Keyboard", toolTip: "Configure Finder keyboard tweaks.") { submenu in
            submenu.addItem(toggleMenuItem(
                title: "Backspace to Trash",
                action: #selector(toggleDeleteKey),
                state: settings.deleteKeyEnabled,
                toolTip: "Maps Backspace/Delete to Finder's Move to Trash command."
            ))
            submenu.addItem(disabledItem(
                shortMenuTitle(keyboardStatusTitle?() ?? "Keyboard Tap: Stopped"),
                toolTip: "Shows whether the keyboard listener is currently active."
            ))
        }
    }

    private func permissionsMenuItem() -> NSMenuItem {
        submenuItem(title: "Permissions", toolTip: "Check Finder extension and privacy permissions.") { submenu in
            let finderExtensionItem = NSMenuItem(
                title: finderExtensionStatusTitle(),
                action: #selector(showFinderExtensionManagement),
                keyEquivalent: ""
            )
            finderExtensionItem.target = self
            finderExtensionItem.toolTip = "Open the macOS Finder Extension management screen."
            submenu.addItem(finderExtensionItem)

            submenu.addItem(.separator())
            submenu.addItem(permissionActionItem(
                grantedTitle: "Accessibility: Granted",
                requestTitle: "Request Accessibility",
                isGranted: KeyboardDeleteController.isAccessibilityTrusted,
                action: #selector(requestAccessibilityPermission),
                toolTip: "Required for fallback menus and keyboard focus checks."
            ))
            submenu.addItem(permissionActionItem(
                grantedTitle: "Input Monitoring: Granted",
                requestTitle: "Request Input Monitoring",
                isGranted: KeyboardDeleteController.canListenToInputEvents,
                action: #selector(requestInputEventPermission),
                toolTip: "Required for the Backspace/Delete keyboard tweak."
            ))

            submenu.addItem(.separator())
            let refreshItem = NSMenuItem(title: "Refresh Status", action: #selector(refreshStatus), keyEquivalent: "")
            refreshItem.target = self
            refreshItem.toolTip = "Refresh permission and controller status."
            submenu.addItem(refreshItem)
        }
    }

    private func finderActionOrderMenuItem() -> NSMenuItem {
        submenuItem(title: "Menu Order", toolTip: "Reorder Finder right-click actions.") { submenu in
            let snapshot = settings.currentSnapshot

            for (index, action) in settings.finderActionOrder.enumerated() {
                let fullActionTitle = "\(index + 1). \(action.title(settings: snapshot))"
                let actionTitle = shortMenuTitle(fullActionTitle)
                let actionItem = submenuItem(title: actionTitle, toolTip: fullActionTitle) { actionMenu in
                    let moveUpItem = finderActionMoveItem(
                        title: "Move Up",
                        action: action,
                        selector: #selector(moveFinderActionUp(_:)),
                        toolTip: "Move \(action.title(settings: snapshot)) earlier in the Finder menu."
                    )
                    moveUpItem.isEnabled = index > 0
                    actionMenu.addItem(moveUpItem)

                    let moveDownItem = finderActionMoveItem(
                        title: "Move Down",
                        action: action,
                        selector: #selector(moveFinderActionDown(_:)),
                        toolTip: "Move \(action.title(settings: snapshot)) later in the Finder menu."
                    )
                    moveDownItem.isEnabled = index < settings.finderActionOrder.count - 1
                    actionMenu.addItem(moveDownItem)
                }
                submenu.addItem(actionItem)
            }

            submenu.addItem(.separator())
            let resetItem = NSMenuItem(title: "Reset Order", action: #selector(resetFinderActionOrder), keyEquivalent: "")
            resetItem.target = self
            resetItem.toolTip = "Restore the default Finder action order."
            submenu.addItem(resetItem)
        }
    }

    private func toggleMenuItem(title: String, action: Selector, state: Bool, toolTip: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = state ? .on : .off
        item.toolTip = toolTip
        return item
    }

    private func submenuItem(title: String, toolTip: String? = nil, build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        build(submenu)
        item.submenu = submenu
        item.toolTip = toolTip
        return item
    }

    private func disabledItem(_ title: String, toolTip: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.toolTip = toolTip
        return item
    }

    private func permissionActionItem(
        grantedTitle: String,
        requestTitle: String,
        isGranted: Bool,
        action: Selector,
        toolTip: String
    ) -> NSMenuItem {
        if isGranted {
            return disabledItem(grantedTitle, toolTip: toolTip)
        }

        let item = NSMenuItem(title: requestTitle, action: action, keyEquivalent: "")
        item.target = self
        item.toolTip = toolTip
        return item
    }

    private func finderActionMoveItem(
        title: String,
        action: FinderMenuAction,
        selector: Selector,
        toolTip: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.representedObject = action.rawValue
        item.toolTip = toolTip
        return item
    }

    private func statusSummaryTitle() -> String {
        guard settings.masterEnabled else {
            return "Paused"
        }

        if !FIFinderSyncController.isExtensionEnabled {
            return "Needs Finder Extension"
        }

        if !KeyboardDeleteController.isAccessibilityTrusted || !KeyboardDeleteController.canListenToInputEvents {
            return "Some permissions needed"
        }

        return "Ready"
    }

    private func finderExtensionStatusTitle() -> String {
        FIFinderSyncController.isExtensionEnabled
            ? "Finder Extension: Enabled"
            : "Enable Finder Extension"
    }

    private func shortMenuTitle(_ title: String, maxLength: Int = 30) -> String {
        guard title.count > maxLength, maxLength > 3 else { return title }
        return String(title.prefix(maxLength - 3)) + "..."
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

    @objc private func toggleOpenContainingFolderForFiles() {
        settings.openContainingFolderForFiles.toggle()
        rebuildMenu()
    }

    @objc private func toggleDeleteKey() {
        settings.deleteKeyEnabled.toggle()
        rebuildMenu()
    }

    @objc private func moveFinderActionUp(_ sender: NSMenuItem) {
        moveFinderAction(sender, by: -1)
    }

    @objc private func moveFinderActionDown(_ sender: NSMenuItem) {
        moveFinderAction(sender, by: 1)
    }

    @objc private func resetFinderActionOrder() {
        settings.resetFinderActionOrder()
        rebuildMenu()
    }

    private func moveFinderAction(_ sender: NSMenuItem, by offset: Int) {
        guard let rawValue = sender.representedObject as? String,
              let action = FinderMenuAction(rawValue: rawValue)
        else {
            return
        }

        settings.moveFinderAction(action, by: offset)
        rebuildMenu()
    }

    @objc private func chooseIDE() {
        let panel = NSOpenPanel()
        panel.title = "Choose IDE"
        panel.message = "Choose the app that should open Finder items."
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.chooseIDEApplication(url)
        rebuildMenu()
    }

    @objc private func chooseTerminal() {
        let panel = NSOpenPanel()
        panel.title = "Choose Terminal"
        panel.message = "Choose the terminal app that should open Finder folders."
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.chooseTerminalApplication(url)
        rebuildMenu()
    }

    @objc private func openSettings() {
        showSettings?()
    }

    @objc private func requestAccessibilityPermission() {
        KeyboardDeleteController.requestAccessibilityPermission()
        refreshControllers?()
        rebuildMenu()
    }

    @objc private func requestInputEventPermission() {
        KeyboardDeleteController.requestInputEventPermission()
        refreshControllers?()
        rebuildMenu()
    }

    @objc private func showFinderExtensionManagement() {
        FIFinderSyncController.showExtensionManagementInterface()
        rebuildMenu()
    }

    @objc private func refreshStatus() {
        refreshControllers?()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
