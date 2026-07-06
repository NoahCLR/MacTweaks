import Cocoa
import FinderSync
import os

final class FinderSync: FIFinderSync {
    private let defaults = SharedDefaults.makeUserDefaults()
    private let logger = Logger(subsystem: "com.noah.MacTweaks", category: "FinderSync")

    override init() {
        super.init()
        diagnosticLog("initialized")
        refreshMonitoredFolders()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(settingsChanged),
            name: SharedDefaults.distributedSettingsDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(volumeTopologyChanged),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(volumeTopologyChanged),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(volumeTopologyChanged),
            name: NSWorkspace.didRenameVolumeNotification,
            object: nil
        )
    }

    override func beginObservingDirectory(at url: URL) {
        diagnosticLog("begin observing \(url.standardizedFileURL.path)")
    }

    override func endObservingDirectory(at url: URL) {
        diagnosticLog("end observing \(url.standardizedFileURL.path)")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let settings = SettingsSnapshot(defaults: defaults)
        guard settings.masterEnabled else { return nil }

        let controller = FIFinderSyncController.default()
        let targetedURL = controller.targetedURL()
        let selectedURLs = controller.selectedItemURLs() ?? []
        diagnosticLog(
            "menu requested kind=\(menuKind.rawValue) target=\(targetedURL?.standardizedFileURL.path ?? "nil") selected=\(selectedURLs.map { $0.standardizedFileURL.path }.joined(separator: "|")) create=\(settings.createFileEnabled) open=\(settings.openInIDEEnabled) copy=\(settings.copyPathEnabled) terminal=\(settings.openTerminalEnabled)"
        )
        let context = FinderMenuContext.finderSync(
            menuKind: FinderMenuKind(menuKind),
            targetedURL: targetedURL,
            selectedURLs: selectedURLs,
            settings: settings
        )
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false

        for action in FinderMenuAction.enabledActions(settings: settings) {
            let item = NSMenuItem(title: action.title(settings: settings), action: selector(for: action), keyEquivalent: "")
            item.target = self
            item.representedObject = context
            item.isEnabled = isEnabledAtMenuBuild(action, settings: settings)
            menu.addItem(item)
        }

        return menu.items.isEmpty ? nil : menu
    }

    @objc private func settingsChanged() {
        refreshMonitoredFolders()
    }

    @objc private func volumeTopologyChanged() {
        refreshMonitoredFolders()
    }

    @objc private func createNewFileHere(_ sender: NSMenuItem) {
        execute(.createNewFileHere, sender: sender)
    }

    @objc private func openInIDE(_ sender: NSMenuItem) {
        execute(.openInIDE, sender: sender)
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        execute(.copyPath, sender: sender)
    }

    @objc private func openTerminalHere(_ sender: NSMenuItem) {
        execute(.openTerminalHere, sender: sender)
    }

    private func selector(for action: FinderMenuAction) -> Selector {
        switch action {
        case .createNewFileHere:
            return #selector(createNewFileHere(_:))
        case .openInIDE:
            return #selector(openInIDE(_:))
        case .copyPath:
            return #selector(copyPath(_:))
        case .openTerminalHere:
            return #selector(openTerminalHere(_:))
        }
    }

    private func isEnabledAtMenuBuild(_ action: FinderMenuAction, settings: SettingsSnapshot) -> Bool {
        switch action {
        case .createNewFileHere, .copyPath:
            return true
        case .openInIDE:
            return settings.ideApplicationURL != nil
        case .openTerminalHere:
            return settings.terminalApplicationURL != nil
        }
    }

    private func execute(_ action: FinderMenuAction, sender: NSMenuItem) {
        let settings = SettingsSnapshot(defaults: defaults)
        guard let context = resolvedContext(for: action, sender: sender, settings: settings) else {
            diagnosticLog("action missing saved context action=\(action.diagnosticName)")
            NSSound.beep()
            return
        }

        let result = FinderMenuActionExecutor.execute(action, context: context, settings: settings)
        switch result {
        case .success(let executionResult):
            diagnosticLog("action succeeded \(executionResult.diagnosticSummary) \(context.diagnosticSummary)")
        case .failure(let error):
            logger.error("Finder Sync action failed: \(error.localizedDescription, privacy: .public)")
            NSLog("Mac Tweaks FinderSync action failed: \(error.localizedDescription) \(context.diagnosticSummary)")
            NSSound.beep()
        }
    }

    private func resolvedContext(
        for action: FinderMenuAction,
        sender: NSMenuItem,
        settings: SettingsSnapshot
    ) -> FinderMenuContext? {
        let savedContext = sender.representedObject as? FinderMenuContext
        if let savedContext {
            let refreshedContext = savedContext.refreshing(settings: settings)
            if FinderMenuActionExecutor.hasResolvedTarget(action, context: refreshedContext) {
                return refreshedContext
            }
        }

        let liveContext = currentFinderContext(
            menuKind: savedContext?.menuKind ?? .contextualMenuForItems,
            settings: settings
        )
        if FinderMenuActionExecutor.hasResolvedTarget(action, context: liveContext) {
            diagnosticLog("action used live Finder context action=\(action.diagnosticName) \(liveContext.diagnosticSummary)")
            return liveContext
        }

        return savedContext?.refreshing(settings: settings) ?? liveContext
    }

    private func currentFinderContext(
        menuKind: FinderMenuKind,
        settings: SettingsSnapshot
    ) -> FinderMenuContext {
        let controller = FIFinderSyncController.default()
        return FinderMenuContext.finderSync(
            menuKind: menuKind,
            targetedURL: controller.targetedURL(),
            selectedURLs: controller.selectedItemURLs() ?? [],
            settings: settings
        )
    }

    private func refreshMonitoredFolders() {
        let settings = SettingsSnapshot(defaults: defaults)
        let monitoredURLs = SharedDefaults.expandedMonitoredFolderURLs(basePaths: settings.monitoredFolderURLs.map(\.path))
        FIFinderSyncController.default().directoryURLs = Set(monitoredURLs)
        let monitoredPaths = monitoredURLs.map(\.path).joined(separator: ", ")
        diagnosticLog("monitoring \(monitoredURLs.count) folders: \(monitoredPaths)")
    }

    private func diagnosticLog(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        NSLog("Mac Tweaks FinderSync: \(message)")
    }
}

private extension FinderMenuKind {
    init(_ menuKind: FIMenuKind) {
        switch menuKind {
        case .contextualMenuForItems:
            self = .contextualMenuForItems
        case .contextualMenuForContainer:
            self = .contextualMenuForContainer
        case .contextualMenuForSidebar:
            self = .contextualMenuForSidebar
        case .toolbarItemMenu:
            self = .toolbarItemMenu
        @unknown default:
            self = .contextualMenuForItems
        }
    }
}
