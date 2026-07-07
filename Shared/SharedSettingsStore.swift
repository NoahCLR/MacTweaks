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
    let clipboardToFileEnabled: Bool
    let pasteImageAsFile: Bool
    let pasteTextAsFile: Bool
    let cutFilesEnabled: Bool
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
        monitoredFolderURLs: [URL],
        clipboardToFileEnabled: Bool = false,
        pasteImageAsFile: Bool = true,
        pasteTextAsFile: Bool = true,
        cutFilesEnabled: Bool = false
    ) {
        self.masterEnabled = masterEnabled
        self.createFileEnabled = createFileEnabled
        self.openInIDEEnabled = openInIDEEnabled
        self.copyPathEnabled = copyPathEnabled
        self.openTerminalEnabled = openTerminalEnabled
        self.enhancedFinderMenusEnabled = enhancedFinderMenusEnabled
        self.deleteKeyEnabled = deleteKeyEnabled
        self.clipboardToFileEnabled = clipboardToFileEnabled
        self.pasteImageAsFile = pasteImageAsFile
        self.pasteTextAsFile = pasteTextAsFile
        self.cutFilesEnabled = cutFilesEnabled
        self.openContainingFolderForFiles = openContainingFolderForFiles
        self.ideApplicationURL = ideApplicationURL
        self.terminalApplicationURL = terminalApplicationURL
        self.finderActionOrder = FinderMenuAction.normalizedOrder(finderActionOrder)
        self.monitoredFolderURLs = monitoredFolderURLs
    }

    init(defaults: UserDefaults = SharedDefaults.makeUserDefaults()) {
        let fileSettings = SharedDefaults.loadSettingsFile()

        // Bool / URL / action-order settings resolve through the registry
        // (file → defaults → built-in default). `monitoredFolderPaths` below is the
        // one exception: it carries bespoke legacy-migration and stays hand-written.
        masterEnabled = SettingsSchema.masterEnabled.resolved(file: fileSettings, defaults: defaults)
        createFileEnabled = SettingsSchema.createFileEnabled.resolved(file: fileSettings, defaults: defaults)
        openInIDEEnabled = SettingsSchema.openInIDEEnabled.resolved(file: fileSettings, defaults: defaults)
        copyPathEnabled = SettingsSchema.copyPathEnabled.resolved(file: fileSettings, defaults: defaults)
        openTerminalEnabled = SettingsSchema.openTerminalEnabled.resolved(file: fileSettings, defaults: defaults)
        enhancedFinderMenusEnabled = SettingsSchema.enhancedFinderMenusEnabled.resolved(file: fileSettings, defaults: defaults)
        deleteKeyEnabled = SettingsSchema.deleteKeyEnabled.resolved(file: fileSettings, defaults: defaults)
        clipboardToFileEnabled = SettingsSchema.clipboardToFileEnabled.resolved(file: fileSettings, defaults: defaults)
        pasteImageAsFile = SettingsSchema.pasteImageAsFile.resolved(file: fileSettings, defaults: defaults)
        pasteTextAsFile = SettingsSchema.pasteTextAsFile.resolved(file: fileSettings, defaults: defaults)
        cutFilesEnabled = SettingsSchema.cutFilesEnabled.resolved(file: fileSettings, defaults: defaults)
        openContainingFolderForFiles = SettingsSchema.openContainingFolderForFiles.resolved(file: fileSettings, defaults: defaults)
        ideApplicationURL = SettingsSchema.ideApplicationURL.resolved(file: fileSettings, defaults: defaults)
        terminalApplicationURL = SettingsSchema.terminalApplicationURL.resolved(file: fileSettings, defaults: defaults)
        finderActionOrder = SettingsSchema.finderActionOrder.resolved(file: fileSettings, defaults: defaults)

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
    @Published var clipboardToFileEnabled: Bool { didSet { save(clipboardToFileEnabled, for: SettingsKey.clipboardToFileEnabled) } }
    @Published var pasteImageAsFile: Bool { didSet { save(pasteImageAsFile, for: SettingsKey.pasteImageAsFile) } }
    @Published var pasteTextAsFile: Bool { didSet { save(pasteTextAsFile, for: SettingsKey.pasteTextAsFile) } }
    @Published var cutFilesEnabled: Bool { didSet { save(cutFilesEnabled, for: SettingsKey.cutFilesEnabled) } }
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
        clipboardToFileEnabled = snapshot.clipboardToFileEnabled
        pasteImageAsFile = snapshot.pasteImageAsFile
        pasteTextAsFile = snapshot.pasteTextAsFile
        cutFilesEnabled = snapshot.cutFilesEnabled
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
        for setting in SettingsSchema.all where defaults.object(forKey: setting.key) == nil {
            defaults.set(setting.currentStored(in: self), forKey: setting.key)
        }
        // monitoredFolderPaths is outside the registry (bespoke legacy migration).
        if defaults.object(forKey: SettingsKey.monitoredFolderPaths) == nil {
            defaults.set(monitoredFolderURLs.map(\.path), forKey: SettingsKey.monitoredFolderPaths)
        }
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
        var values: [String: Any] = [:]
        for setting in SettingsSchema.all {
            values[setting.key] = setting.currentStored(in: self)
        }
        // monitoredFolderPaths is outside the registry (bespoke legacy migration).
        values[SettingsKey.monitoredFolderPaths] = monitoredFolderURLs.map(\.path)
        SharedDefaults.writeSettingsFile(values)
    }

    private func notifyChanged() {
        defaults.synchronize()
        NotificationCenter.default.post(name: SharedDefaults.settingsDidChangeNotification, object: self)
        DistributedNotificationCenter.default().post(name: SharedDefaults.distributedSettingsDidChangeNotification, object: nil)
    }
}
