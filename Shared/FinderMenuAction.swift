import Foundation

enum FinderMenuSource: String {
    case finderSync
    case compatibilityFallback
    case services
}

enum FinderMenuKind: String {
    case contextualMenuForItems
    case contextualMenuForContainer
    case contextualMenuForSidebar
    case toolbarItemMenu
    case servicesMenu
}

enum FinderMenuAction: String, CaseIterable, Identifiable {
    case createNewFileHere
    case openInIDE
    case copyPath
    case openTerminalHere

    static let defaultOrder: [FinderMenuAction] = [
        .createNewFileHere,
        .openInIDE,
        .copyPath,
        .openTerminalHere
    ]

    var id: String {
        rawValue
    }

    static func enabledActions(settings: SettingsSnapshot) -> [FinderMenuAction] {
        settings.finderActionOrder.filter { $0.isEnabled(settings: settings) }
    }

    static func normalizedOrder(rawValues: [String]?) -> [FinderMenuAction] {
        guard let rawValues else {
            return defaultOrder
        }

        let parsedActions = rawValues.compactMap(FinderMenuAction.init(rawValue:))
        return normalizedOrder(parsedActions)
    }

    static func normalizedOrder(_ actions: [FinderMenuAction]) -> [FinderMenuAction] {
        var seen = Set<FinderMenuAction>()
        var orderedActions: [FinderMenuAction] = []

        for action in actions where seen.insert(action).inserted {
            orderedActions.append(action)
        }

        for action in defaultOrder where seen.insert(action).inserted {
            orderedActions.append(action)
        }

        return orderedActions
    }

    var diagnosticName: String {
        rawValue
    }

    func title(settings: SettingsSnapshot) -> String {
        switch self {
        case .createNewFileHere:
            return "Create New File Here"
        case .openInIDE:
            let ideName = settings.ideApplicationURL?.deletingPathExtension().lastPathComponent ?? "IDE"
            return "Open in \(ideName)"
        case .copyPath:
            return "Copy Path"
        case .openTerminalHere:
            let terminalName = settings.terminalApplicationURL?.deletingPathExtension().lastPathComponent ?? "Terminal"
            return "Open in \(terminalName)"
        }
    }

    func isEnabled(settings: SettingsSnapshot) -> Bool {
        switch self {
        case .createNewFileHere:
            return settings.createFileEnabled
        case .openInIDE:
            return settings.openInIDEEnabled
        case .copyPath:
            return settings.copyPathEnabled
        case .openTerminalHere:
            return settings.openTerminalEnabled
        }
    }
}

final class FinderMenuContext: NSObject {
    let source: FinderMenuSource
    let menuKind: FinderMenuKind
    let currentFolderURL: URL?
    let clickedItemURL: URL?
    let targetedURL: URL?
    let selectedURLs: [URL]
    let createDirectory: URL?
    let openTarget: URL?
    let copyPathURLs: [URL]
    let terminalDirectory: URL?

    init(
        source: FinderMenuSource,
        menuKind: FinderMenuKind,
        currentFolderURL: URL? = nil,
        clickedItemURL: URL? = nil,
        targetedURL: URL?,
        selectedURLs: [URL],
        openContainingFolderForFiles: Bool
    ) {
        let standardizedCurrentFolder = currentFolderURL?.standardizedFileURL
        let standardizedClickedItem = clickedItemURL?.standardizedFileURL
        let standardizedTarget = targetedURL?.standardizedFileURL
        let standardizedSelection = FinderMenuContext.uniqueStandardizedURLs(selectedURLs)
        let actionInput = FinderMenuContext.actionInput(
            menuKind: menuKind,
            targetedURL: standardizedTarget,
            selectedURLs: standardizedSelection
        )
        let pathCopyTargets = FinderMenuContext.pathCopyTargets(
            source: source,
            menuKind: menuKind,
            clickedItemURL: standardizedClickedItem,
            targetedURL: standardizedTarget,
            selectedURLs: standardizedSelection
        )

        self.source = source
        self.menuKind = menuKind
        self.currentFolderURL = standardizedCurrentFolder
        self.clickedItemURL = standardizedClickedItem
        self.targetedURL = standardizedTarget
        self.selectedURLs = standardizedSelection
        createDirectory = FinderActionService.targetDirectory(
            clickedURL: actionInput.clickedURL,
            selectedURLs: actionInput.selectedURLs
        )
        openTarget = FinderActionService.openTarget(
            clickedURL: actionInput.clickedURL,
            selectedURLs: actionInput.selectedURLs,
            openContainingFolderForFiles: openContainingFolderForFiles
        )
        copyPathURLs = pathCopyTargets
        terminalDirectory = FinderActionService.targetDirectory(clickedURL: pathCopyTargets.first, selectedURLs: [])

        super.init()
    }

    static func finderSync(
        menuKind: FinderMenuKind,
        targetedURL: URL?,
        selectedURLs: [URL],
        settings: SettingsSnapshot
    ) -> FinderMenuContext {
        FinderMenuContext(
            source: .finderSync,
            menuKind: menuKind,
            targetedURL: targetedURL,
            selectedURLs: selectedURLs,
            openContainingFolderForFiles: settings.openContainingFolderForFiles
        )
    }

    static func compatibilityFallback(
        currentFolderURL: URL,
        clickedItemURL: URL?,
        selectedURLs: [URL],
        settings: SettingsSnapshot
    ) -> FinderMenuContext {
        FinderMenuContext(
            source: .compatibilityFallback,
            menuKind: clickedItemURL == nil ? .contextualMenuForContainer : .contextualMenuForItems,
            currentFolderURL: currentFolderURL,
            clickedItemURL: clickedItemURL,
            targetedURL: clickedItemURL ?? currentFolderURL,
            selectedURLs: selectedURLs,
            openContainingFolderForFiles: settings.openContainingFolderForFiles
        )
    }

    static func services(
        selectedURLs: [URL],
        settings: SettingsSnapshot
    ) -> FinderMenuContext {
        FinderMenuContext(
            source: .services,
            menuKind: .servicesMenu,
            targetedURL: nil,
            selectedURLs: selectedURLs,
            openContainingFolderForFiles: settings.openContainingFolderForFiles
        )
    }

    func refreshing(settings: SettingsSnapshot) -> FinderMenuContext {
        FinderMenuContext(
            source: source,
            menuKind: menuKind,
            currentFolderURL: currentFolderURL,
            clickedItemURL: clickedItemURL,
            targetedURL: targetedURL,
            selectedURLs: selectedURLs,
            openContainingFolderForFiles: settings.openContainingFolderForFiles
        )
    }

    private static func actionInput(
        menuKind: FinderMenuKind,
        targetedURL: URL?,
        selectedURLs: [URL]
    ) -> (clickedURL: URL?, selectedURLs: [URL]) {
        switch menuKind {
        case .contextualMenuForContainer:
            return (targetedURL, [])
        case .contextualMenuForItems, .contextualMenuForSidebar, .toolbarItemMenu:
            if let targetedURL {
                return (targetedURL, [])
            }
            return (nil, selectedURLs)
        case .servicesMenu:
            return (nil, selectedURLs)
        }
    }

    private static func uniqueStandardizedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var uniqueURLs: [URL] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            uniqueURLs.append(standardized)
        }

        return uniqueURLs
    }

    var diagnosticSummary: String {
        let selectedPaths = selectedURLs.map(\.path).joined(separator: "|")
        return [
            "source=\(source.rawValue)",
            "kind=\(menuKind.rawValue)",
            "current=\(currentFolderURL?.path ?? "nil")",
            "clicked=\(clickedItemURL?.path ?? "nil")",
            "target=\(targetedURL?.path ?? "nil")",
            "createDirectory=\(createDirectory?.path ?? "nil")",
            "openTarget=\(openTarget?.path ?? "nil")",
            "copyPathTargets=\(copyPathURLs.map(\.path).joined(separator: "|"))",
            "terminalDirectory=\(terminalDirectory?.path ?? "nil")",
            "selected=\(selectedPaths.isEmpty ? "none" : selectedPaths)"
        ].joined(separator: " ")
    }

    private static func pathCopyTargets(
        source: FinderMenuSource,
        menuKind: FinderMenuKind,
        clickedItemURL: URL?,
        targetedURL: URL?,
        selectedURLs: [URL]
    ) -> [URL] {
        switch menuKind {
        case .contextualMenuForContainer:
            if let targetedURL {
                return [targetedURL]
            }
            return selectedURLs
        case .contextualMenuForItems:
            if source == .compatibilityFallback, let clickedItemURL {
                return [clickedItemURL]
            }
            if !selectedURLs.isEmpty {
                return selectedURLs
            }
            if let targetedURL {
                return [targetedURL]
            }
            return []
        case .contextualMenuForSidebar, .toolbarItemMenu:
            if let targetedURL {
                return [targetedURL]
            }
            return selectedURLs
        case .servicesMenu:
            return selectedURLs
        }
    }
}

struct FinderMenuActionExecutionResult {
    let action: FinderMenuAction
    let urls: [URL]

    init(action: FinderMenuAction, url: URL) {
        self.action = action
        urls = [url]
    }

    init(action: FinderMenuAction, urls: [URL]) {
        self.action = action
        self.urls = urls
    }

    var diagnosticSummary: String {
        let paths = urls.map { $0.standardizedFileURL.path }.joined(separator: "|")
        return "action=\(action.diagnosticName) urls=\(paths)"
    }
}

enum FinderMenuActionExecutor {
    static func hasResolvedTarget(_ action: FinderMenuAction, context: FinderMenuContext) -> Bool {
        switch action {
        case .createNewFileHere:
            return context.createDirectory != nil
        case .openInIDE:
            return context.openTarget != nil
        case .copyPath:
            return !context.copyPathURLs.isEmpty
        case .openTerminalHere:
            return context.terminalDirectory != nil
        }
    }

    static func canPerform(
        _ action: FinderMenuAction,
        context: FinderMenuContext,
        settings: SettingsSnapshot
    ) -> Bool {
        guard settings.masterEnabled else { return false }

        switch action {
        case .createNewFileHere:
            return settings.createFileEnabled && hasResolvedTarget(action, context: context)
        case .openInIDE:
            return settings.openInIDEEnabled
                && hasResolvedTarget(action, context: context)
                && settings.ideApplicationURL != nil
        case .copyPath:
            return settings.copyPathEnabled && hasResolvedTarget(action, context: context)
        case .openTerminalHere:
            return settings.openTerminalEnabled
                && hasResolvedTarget(action, context: context)
                && settings.terminalApplicationURL != nil
        }
    }

    @discardableResult
    static func execute(
        _ action: FinderMenuAction,
        context: FinderMenuContext,
        settings: SettingsSnapshot
    ) -> Result<FinderMenuActionExecutionResult, Error> {
        guard settings.masterEnabled else {
            return .failure(FinderActionError.actionDisabled)
        }

        do {
            switch action {
            case .createNewFileHere:
                guard settings.createFileEnabled else {
                    return .failure(FinderActionError.actionDisabled)
                }
                guard let directory = context.createDirectory else {
                    return .failure(FinderActionError.cannotResolveTargetDirectory)
                }

                let createdURL = try FinderActionService.createUntitledFile(in: directory)
                FinderActionService.revealInFinder(createdURL)
                return .success(FinderMenuActionExecutionResult(action: action, url: createdURL))

            case .openInIDE:
                guard settings.openInIDEEnabled else {
                    return .failure(FinderActionError.actionDisabled)
                }
                guard let target = context.openTarget else {
                    return .failure(FinderActionError.cannotResolveTargetDirectory)
                }

                try FinderActionService.openInIDE(targetURL: target, ideApplicationURL: settings.ideApplicationURL)
                return .success(FinderMenuActionExecutionResult(action: action, url: target))

            case .copyPath:
                guard settings.copyPathEnabled else {
                    return .failure(FinderActionError.actionDisabled)
                }
                guard !context.copyPathURLs.isEmpty else {
                    return .failure(FinderActionError.cannotResolveTargetDirectory)
                }

                try FinderActionService.copyPathsToClipboard(context.copyPathURLs)
                return .success(FinderMenuActionExecutionResult(action: action, urls: context.copyPathURLs))

            case .openTerminalHere:
                guard settings.openTerminalEnabled else {
                    return .failure(FinderActionError.actionDisabled)
                }
                guard let directory = context.terminalDirectory else {
                    return .failure(FinderActionError.cannotResolveTargetDirectory)
                }

                try FinderActionService.openTerminal(at: directory, terminalApplicationURL: settings.terminalApplicationURL)
                return .success(FinderMenuActionExecutionResult(action: action, url: directory))
            }
        } catch {
            return .failure(error)
        }
    }
}
