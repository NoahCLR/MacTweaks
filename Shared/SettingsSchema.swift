import Foundation

/// Type-erased face of a setting, used to iterate every setting for the
/// persistence machinery (write-defaults-if-missing, file persistence).
protocol SettingSpec {
    var key: String { get }
    /// The default, encoded into its stored (property-list) representation.
    var defaultStored: Any { get }
    /// The store's current value, encoded into its stored representation.
    func currentStored(in store: SharedSettingsStore) -> Any
}

/// A single setting declared once: its key, in-memory default, and how its typed
/// value maps to the plist / UserDefaults representation. The read/fallback order
/// and the persistence machinery derive from these, so a setting can't be half-
/// wired (present in one storage layer but silently dropped from another).
struct Setting<Value>: SettingSpec {
    let key: String
    let defaultValue: Value
    /// Decode a stored property-list value (or nil) into the typed value,
    /// falling back to `defaultValue`.
    let decode: (Any?) -> Value
    /// Encode the typed value into a property-list value for storage.
    let encode: (Value) -> Any
    /// The matching store property, for reading the current value on persist.
    let read: KeyPath<SharedSettingsStore, Value>

    /// The effective value: the settings file wins, then the defaults suite,
    /// then the built-in default. Mirrors the dual-layer read order.
    func resolved(file: [String: Any], defaults: UserDefaults) -> Value {
        decode(file[key] ?? defaults.object(forKey: key))
    }

    var defaultStored: Any { encode(defaultValue) }

    func currentStored(in store: SharedSettingsStore) -> Any {
        encode(store[keyPath: read])
    }
}

extension Setting where Value == Bool {
    init(_ key: String, default defaultValue: Bool, read: KeyPath<SharedSettingsStore, Bool>) {
        self.init(
            key: key,
            defaultValue: defaultValue,
            decode: { ($0 as? Bool) ?? defaultValue },
            encode: { $0 },
            read: read
        )
    }
}

extension Setting where Value == [String] {
    init(_ key: String, default defaultValue: [String], read: KeyPath<SharedSettingsStore, [String]>) {
        self.init(
            key: key,
            defaultValue: defaultValue,
            decode: { ($0 as? [String]) ?? defaultValue },
            encode: { $0 },
            read: read
        )
    }
}

extension Setting where Value == URL? {
    /// URL settings store a POSIX path string; an empty/absent value means "use
    /// the app's current default", which is recomputed fresh (e.g. the installed
    /// IDE may change), matching the pre-registry behavior.
    init(_ key: String, appDefault: @escaping () -> URL?, read: KeyPath<SharedSettingsStore, URL?>) {
        self.init(
            key: key,
            defaultValue: appDefault(),
            decode: { stored in
                if let path = stored as? String, !path.isEmpty {
                    return URL(fileURLWithPath: path)
                }
                return appDefault()
            },
            encode: { $0?.path ?? "" },
            read: read
        )
    }
}

extension Setting where Value == [FinderMenuAction] {
    init(_ key: String, default defaultValue: [FinderMenuAction], read: KeyPath<SharedSettingsStore, [FinderMenuAction]>) {
        self.init(
            key: key,
            defaultValue: defaultValue,
            decode: { FinderMenuAction.normalizedOrder(rawValues: $0 as? [String]) },
            encode: { $0.map(\.rawValue) },
            read: read
        )
    }
}

/// The single declaration site for every setting. `monitoredFolderPaths` is
/// intentionally absent — it carries bespoke legacy-migration on read and stays
/// hand-written in `SettingsSnapshot` (see the note there).
enum SettingsSchema {
    static let masterEnabled = Setting(SettingsKey.masterEnabled, default: true, read: \.masterEnabled)
    static let createFileEnabled = Setting(SettingsKey.createFileEnabled, default: true, read: \.createFileEnabled)
    static let openInIDEEnabled = Setting(SettingsKey.openInIDEEnabled, default: true, read: \.openInIDEEnabled)
    static let copyPathEnabled = Setting(SettingsKey.copyPathEnabled, default: true, read: \.copyPathEnabled)
    static let openTerminalEnabled = Setting(SettingsKey.openTerminalEnabled, default: true, read: \.openTerminalEnabled)
    static let enhancedFinderMenusEnabled = Setting(SettingsKey.enhancedFinderMenusEnabled, default: true, read: \.enhancedFinderMenusEnabled)
    static let deleteKeyEnabled = Setting(SettingsKey.deleteKeyEnabled, default: false, read: \.deleteKeyEnabled)
    static let clipboardToFileEnabled = Setting(SettingsKey.clipboardToFileEnabled, default: false, read: \.clipboardToFileEnabled)
    static let pasteImageAsFile = Setting(SettingsKey.pasteImageAsFile, default: true, read: \.pasteImageAsFile)
    static let pasteTextAsFile = Setting(SettingsKey.pasteTextAsFile, default: true, read: \.pasteTextAsFile)
    static let cutFilesEnabled = Setting(SettingsKey.cutFilesEnabled, default: false, read: \.cutFilesEnabled)
    static let openContainingFolderForFiles = Setting(SettingsKey.openContainingFolderForFiles, default: false, read: \.openContainingFolderForFiles)
    static let ideApplicationURL = Setting(SettingsKey.ideApplicationPath, appDefault: FinderActionService.defaultIDEApplicationURL, read: \.ideApplicationURL)
    static let terminalApplicationURL = Setting(SettingsKey.terminalApplicationPath, appDefault: FinderActionService.defaultTerminalApplicationURL, read: \.terminalApplicationURL)
    static let finderActionOrder = Setting(SettingsKey.finderActionOrder, default: FinderMenuAction.defaultOrder, read: \.finderActionOrder)

    /// Every registry-backed setting, in declaration order. Drives
    /// write-defaults-if-missing and file persistence.
    static let all: [SettingSpec] = [
        masterEnabled, createFileEnabled, openInIDEEnabled, copyPathEnabled,
        openTerminalEnabled, enhancedFinderMenusEnabled, deleteKeyEnabled,
        clipboardToFileEnabled, pasteImageAsFile, pasteTextAsFile, cutFilesEnabled,
        openContainingFolderForFiles, ideApplicationURL, terminalApplicationURL,
        finderActionOrder
    ]
}
