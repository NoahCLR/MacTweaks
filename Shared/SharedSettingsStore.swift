import Foundation
import Combine

struct SettingsSnapshot {
    let masterEnabled: Bool
    let createFileEnabled: Bool
    let openInIDEEnabled: Bool
    let copyPathEnabled: Bool
    let openTerminalEnabled: Bool
    let enhancedFinderMenusEnabled: Bool
    let deleteKeyEnabled: Bool
    let openContainingFolderForFiles: Bool
    let ideApplicationURL: URL?
    let terminalApplicationURL: URL?
    let finderActionOrder: [FinderMenuAction]
    let monitoredFolderURLs: [URL]

    init(
        masterEnabled: Bool,
        createFileEnabled: Bool,
        openInIDEEnabled: Bool,
        copyPathEnabled: Bool,
        openTerminalEnabled: Bool,
        enhancedFinderMenusEnabled: Bool,
        deleteKeyEnabled: Bool,
        openContainingFolderForFiles: Bool,
        ideApplicationURL: URL?,
        terminalApplicationURL: URL?,
        finderActionOrder: [FinderMenuAction],
        monitoredFolderURLs: [URL]
    ) {
        self.masterEnabled = masterEnabled
        self.createFileEnabled = createFileEnabled
        self.openInIDEEnabled = openInIDEEnabled
        self.copyPathEnabled = copyPathEnabled
        self.openTerminalEnabled = openTerminalEnabled
        self.enhancedFinderMenusEnabled = enhancedFinderMenusEnabled
        self.deleteKeyEnabled = deleteKeyEnabled
        self.openContainingFolderForFiles = openContainingFolderForFiles
        self.ideApplicationURL = ideApplicationURL
        self.terminalApplicationURL = terminalApplicationURL
        self.finderActionOrder = FinderMenuAction.normalizedOrder(finderActionOrder)
        self.monitoredFolderURLs = monitoredFolderURLs
    }

    init(defaults: UserDefaults = SharedDefaults.makeUserDefaults()) {
        let fileSettings = SharedDefaults.loadSettingsFile()

        masterEnabled = fileSettings[SettingsKey.masterEnabled] as? Bool
            ?? defaults.object(forKey: SettingsKey.masterEnabled) as? Bool
            ?? true
        createFileEnabled = fileSettings[SettingsKey.createFileEnabled] as? Bool
            ?? defaults.object(forKey: SettingsKey.createFileEnabled) as? Bool
            ?? true
        openInIDEEnabled = fileSettings[SettingsKey.openInIDEEnabled] as? Bool
            ?? defaults.object(forKey: SettingsKey.openInIDEEnabled) as? Bool
            ?? true
        copyPathEnabled = fileSettings[SettingsKey.copyPathEnabled] as? Bool
            ?? defaults.object(forKey: SettingsKey.copyPathEnabled) as? Bool
            ?? true
        openTerminalEnabled = fileSettings[SettingsKey.openTerminalEnabled] as? Bool
            ?? defaults.object(forKey: SettingsKey.openTerminalEnabled) as? Bool
            ?? true
        enhancedFinderMenusEnabled = fileSettings[SettingsKey.enhancedFinderMenusEnabled] as? Bool
            ?? defaults.object(forKey: SettingsKey.enhancedFinderMenusEnabled) as? Bool
            ?? true
        deleteKeyEnabled = fileSettings[SettingsKey.deleteKeyEnabled] as? Bool
            ?? defaults.object(forKey: SettingsKey.deleteKeyEnabled) as? Bool
            ?? false
        openContainingFolderForFiles = fileSettings[SettingsKey.openContainingFolderForFiles] as? Bool
            ?? defaults.object(forKey: SettingsKey.openContainingFolderForFiles) as? Bool
            ?? false

        if let path = fileSettings[SettingsKey.ideApplicationPath] as? String, !path.isEmpty {
            ideApplicationURL = URL(fileURLWithPath: path)
        } else if let path = defaults.string(forKey: SettingsKey.ideApplicationPath), !path.isEmpty {
            ideApplicationURL = URL(fileURLWithPath: path)
        } else {
            ideApplicationURL = FinderActionService.defaultIDEApplicationURL()
        }

        if let path = fileSettings[SettingsKey.terminalApplicationPath] as? String, !path.isEmpty {
            terminalApplicationURL = URL(fileURLWithPath: path)
        } else if let path = defaults.string(forKey: SettingsKey.terminalApplicationPath), !path.isEmpty {
            terminalApplicationURL = URL(fileURLWithPath: path)
        } else {
            terminalApplicationURL = FinderActionService.defaultTerminalApplicationURL()
        }

        let storedActionOrder = fileSettings[SettingsKey.finderActionOrder] as? [String]
            ?? defaults.stringArray(forKey: SettingsKey.finderActionOrder)
        finderActionOrder = FinderMenuAction.normalizedOrder(rawValues: storedActionOrder)

        let storedPaths = fileSettings[SettingsKey.monitoredFolderPaths] as? [String]
            ?? defaults.stringArray(forKey: SettingsKey.monitoredFolderPaths)
        let paths: [String]
        if let storedPaths, storedPaths.isEmpty == false {
            paths = storedPaths == SharedDefaults.legacyDefaultMonitoredFolderPaths()
                ? SharedDefaults.defaultMonitoredFolderPaths()
                : storedPaths
        } else {
            paths = SharedDefaults.defaultMonitoredFolderPaths()
        }
        monitoredFolderURLs = paths.map { URL(fileURLWithPath: $0) }
    }
}

final class SharedSettingsStore: ObservableObject {
    @Published var masterEnabled: Bool { didSet { save(masterEnabled, for: SettingsKey.masterEnabled) } }
    @Published var createFileEnabled: Bool { didSet { save(createFileEnabled, for: SettingsKey.createFileEnabled) } }
    @Published var openInIDEEnabled: Bool { didSet { save(openInIDEEnabled, for: SettingsKey.openInIDEEnabled) } }
    @Published var copyPathEnabled: Bool { didSet { save(copyPathEnabled, for: SettingsKey.copyPathEnabled) } }
    @Published var openTerminalEnabled: Bool { didSet { save(openTerminalEnabled, for: SettingsKey.openTerminalEnabled) } }
    @Published var enhancedFinderMenusEnabled: Bool { didSet { save(enhancedFinderMenusEnabled, for: SettingsKey.enhancedFinderMenusEnabled) } }
    @Published var deleteKeyEnabled: Bool { didSet { save(deleteKeyEnabled, for: SettingsKey.deleteKeyEnabled) } }
    @Published var openContainingFolderForFiles: Bool { didSet { save(openContainingFolderForFiles, for: SettingsKey.openContainingFolderForFiles) } }
    @Published var ideApplicationURL: URL? { didSet { save(ideApplicationURL?.path ?? "", for: SettingsKey.ideApplicationPath) } }
    @Published var terminalApplicationURL: URL? { didSet { save(terminalApplicationURL?.path ?? "", for: SettingsKey.terminalApplicationPath) } }
    @Published var finderActionOrder: [FinderMenuAction] { didSet { save(finderActionOrder.map(\.rawValue), for: SettingsKey.finderActionOrder) } }
    @Published var monitoredFolderURLs: [URL] { didSet { save(monitoredFolderURLs.map(\.path), for: SettingsKey.monitoredFolderPaths) } }

    private let defaults: UserDefaults
    private var isLoading = true

    init(defaults: UserDefaults = SharedDefaults.makeUserDefaults()) {
        self.defaults = defaults
        let snapshot = SettingsSnapshot(defaults: defaults)
        masterEnabled = snapshot.masterEnabled
        createFileEnabled = snapshot.createFileEnabled
        openInIDEEnabled = snapshot.openInIDEEnabled
        copyPathEnabled = snapshot.copyPathEnabled
        openTerminalEnabled = snapshot.openTerminalEnabled
        enhancedFinderMenusEnabled = snapshot.enhancedFinderMenusEnabled
        deleteKeyEnabled = snapshot.deleteKeyEnabled
        openContainingFolderForFiles = snapshot.openContainingFolderForFiles
        ideApplicationURL = snapshot.ideApplicationURL
        terminalApplicationURL = snapshot.terminalApplicationURL
        finderActionOrder = snapshot.finderActionOrder
        monitoredFolderURLs = snapshot.monitoredFolderURLs
        isLoading = false
        writeDefaultsIfMissing()
    }

    var currentSnapshot: SettingsSnapshot {
        SettingsSnapshot(defaults: defaults)
    }

    func chooseIDEApplication(_ url: URL) {
        ideApplicationURL = url
    }

    func chooseTerminalApplication(_ url: URL) {
        terminalApplicationURL = url
    }

    func moveFinderAction(_ action: FinderMenuAction, by offset: Int) {
        guard let currentIndex = finderActionOrder.firstIndex(of: action) else { return }
        let newIndex = currentIndex + offset
        guard finderActionOrder.indices.contains(newIndex) else { return }

        var updatedOrder = finderActionOrder
        updatedOrder.swapAt(currentIndex, newIndex)
        finderActionOrder = FinderMenuAction.normalizedOrder(updatedOrder)
    }

    func moveFinderActions(from offsets: IndexSet, to destination: Int) {
        let validOffsets = offsets.filter { finderActionOrder.indices.contains($0) }.sorted()
        guard !validOffsets.isEmpty else { return }

        let movingActions = validOffsets.map { finderActionOrder[$0] }
        var remainingActions = finderActionOrder.enumerated()
            .filter { !validOffsets.contains($0.offset) }
            .map(\.element)
        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertionIndex = max(0, min(destination - removedBeforeDestination, remainingActions.count))

        remainingActions.insert(contentsOf: movingActions, at: insertionIndex)
        finderActionOrder = FinderMenuAction.normalizedOrder(remainingActions)
    }

    func resetFinderActionOrder() {
        finderActionOrder = FinderMenuAction.defaultOrder
    }

    func addMonitoredFolder(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !monitoredFolderURLs.contains(where: { $0.standardizedFileURL == standardized }) else { return }
        monitoredFolderURLs.append(standardized)
    }

    func removeMonitoredFolders(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where monitoredFolderURLs.indices.contains(index) {
            monitoredFolderURLs.remove(at: index)
        }
    }

    func resetMonitoredFolders() {
        monitoredFolderURLs = SharedDefaults.defaultMonitoredFolderPaths().map { URL(fileURLWithPath: $0) }
    }

    private func writeDefaultsIfMissing() {
        if defaults.object(forKey: SettingsKey.masterEnabled) == nil { defaults.set(masterEnabled, forKey: SettingsKey.masterEnabled) }
        if defaults.object(forKey: SettingsKey.createFileEnabled) == nil { defaults.set(createFileEnabled, forKey: SettingsKey.createFileEnabled) }
        if defaults.object(forKey: SettingsKey.openInIDEEnabled) == nil { defaults.set(openInIDEEnabled, forKey: SettingsKey.openInIDEEnabled) }
        if defaults.object(forKey: SettingsKey.copyPathEnabled) == nil { defaults.set(copyPathEnabled, forKey: SettingsKey.copyPathEnabled) }
        if defaults.object(forKey: SettingsKey.openTerminalEnabled) == nil { defaults.set(openTerminalEnabled, forKey: SettingsKey.openTerminalEnabled) }
        if defaults.object(forKey: SettingsKey.enhancedFinderMenusEnabled) == nil { defaults.set(enhancedFinderMenusEnabled, forKey: SettingsKey.enhancedFinderMenusEnabled) }
        if defaults.object(forKey: SettingsKey.deleteKeyEnabled) == nil { defaults.set(deleteKeyEnabled, forKey: SettingsKey.deleteKeyEnabled) }
        if defaults.object(forKey: SettingsKey.openContainingFolderForFiles) == nil { defaults.set(openContainingFolderForFiles, forKey: SettingsKey.openContainingFolderForFiles) }
        if defaults.object(forKey: SettingsKey.ideApplicationPath) == nil { defaults.set(ideApplicationURL?.path ?? "", forKey: SettingsKey.ideApplicationPath) }
        if defaults.object(forKey: SettingsKey.terminalApplicationPath) == nil { defaults.set(terminalApplicationURL?.path ?? "", forKey: SettingsKey.terminalApplicationPath) }
        if defaults.object(forKey: SettingsKey.finderActionOrder) == nil { defaults.set(finderActionOrder.map(\.rawValue), forKey: SettingsKey.finderActionOrder) }
        if defaults.object(forKey: SettingsKey.monitoredFolderPaths) == nil { defaults.set(monitoredFolderURLs.map(\.path), forKey: SettingsKey.monitoredFolderPaths) }
        persistSettingsFile()
        notifyChanged()
    }

    private func save(_ value: Any, for key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
        persistSettingsFile()
        notifyChanged()
    }

    private func persistSettingsFile() {
        SharedDefaults.writeSettingsFile([
            SettingsKey.masterEnabled: masterEnabled,
            SettingsKey.createFileEnabled: createFileEnabled,
            SettingsKey.openInIDEEnabled: openInIDEEnabled,
            SettingsKey.copyPathEnabled: copyPathEnabled,
            SettingsKey.openTerminalEnabled: openTerminalEnabled,
            SettingsKey.enhancedFinderMenusEnabled: enhancedFinderMenusEnabled,
            SettingsKey.deleteKeyEnabled: deleteKeyEnabled,
            SettingsKey.openContainingFolderForFiles: openContainingFolderForFiles,
            SettingsKey.ideApplicationPath: ideApplicationURL?.path ?? "",
            SettingsKey.terminalApplicationPath: terminalApplicationURL?.path ?? "",
            SettingsKey.finderActionOrder: finderActionOrder.map(\.rawValue),
            SettingsKey.monitoredFolderPaths: monitoredFolderURLs.map(\.path)
        ])
    }

    private func notifyChanged() {
        defaults.synchronize()
        NotificationCenter.default.post(name: SharedDefaults.settingsDidChangeNotification, object: self)
        DistributedNotificationCenter.default().post(name: SharedDefaults.distributedSettingsDidChangeNotification, object: nil)
    }
}
