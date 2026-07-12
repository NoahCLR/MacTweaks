import Foundation
import Darwin

enum SettingsKey {
    static let masterEnabled = "masterEnabled"
    static let createFileEnabled = "createFileEnabled"
    static let openInIDEEnabled = "openInIDEEnabled"
    static let copyPathEnabled = "copyPathEnabled"
    static let openTerminalEnabled = "openTerminalEnabled"
    static let enhancedFinderMenusEnabled = "enhancedFinderMenusEnabled"
    static let deleteKeyEnabled = "deleteKeyEnabled"
    static let clipboardToFileEnabled = "clipboardToFileEnabled"
    static let pasteImageAsFile = "pasteImageAsFile"
    static let pasteTextAsFile = "pasteTextAsFile"
    static let cutFilesEnabled = "cutFilesEnabled"
    static let openContainingFolderForFiles = "openContainingFolderForFiles"
    static let ideApplicationPath = "ideApplicationPath"
    static let terminalApplicationPath = "terminalApplicationPath"
    static let finderActionOrder = "finderActionOrder"
    static let ocrEnabled = "ocrEnabled"
    static let ocrHotKey = "ocrHotKey"
    static let monitoredFolderPaths = "monitoredFolderPaths"
    static let launchAtLoginEnabled = "launchAtLoginEnabled"
}

enum SharedDefaults {
    static let settingsSuiteName = "com.ncleroy.MacTweaks.shared"
    static let settingsDidChangeNotification = Notification.Name("com.ncleroy.MacTweaks.settingsDidChange")
    static let distributedSettingsDidChangeNotification = Notification.Name("com.ncleroy.MacTweaks.distributedSettingsDidChange")
    private static let settingsFileRelativePath = "Library/Application Support/Mac Tweaks/Settings.plist"

    static func makeUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: settingsSuiteName) ?? .standard
    }

    static func defaultMonitoredFolderPaths() -> [String] {
        ["/"]
    }

    static func expandedMonitoredFolderURLs(basePaths: [String]) -> [URL] {
        var urls = basePaths.map { URL(fileURLWithPath: $0) }
        if urls.contains(where: isRootCoverageRequest) {
            urls.append(contentsOf: finderSyncRootCoverageURLs())
        }
        urls.append(URL(fileURLWithPath: "/Volumes"))
        urls.append(contentsOf: mountedVolumeURLs())
        urls.append(contentsOf: cloudStorageURLs())

        return uniqueURLs(urls)
    }

    static func legacyDefaultMonitoredFolderPaths() -> [String] {
        let home = realHomeDirectory()
        return [
            home.path,
            home.appendingPathComponent("Desktop").path,
            home.appendingPathComponent("Documents").path,
            home.appendingPathComponent("Downloads").path
        ]
    }

    static func loadSettingsFile() -> [String: Any] {
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let data = try? Data(contentsOf: settingsFileURL()),
              let values = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
            return [:]
        }
        return values
    }

    static func writeSettingsFile(_ values: [String: Any]) {
        let url = settingsFileURL()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Mac Tweaks could not write shared settings file: \(error.localizedDescription)")
        }
    }

    static func settingsFileURL() -> URL {
        realHomeDirectory().appendingPathComponent(settingsFileRelativePath)
    }

    private static func mountedVolumeURLs() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsBrowsableKey, .volumeURLKey]
        let mountedURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        let visibleMountedURLs = mountedURLs.filter { url in
            guard url.path.hasPrefix("/Volumes/") else { return true }
            let name = url.lastPathComponent
            return !name.hasPrefix(".") && name != "com.apple.TimeMachine.localsnapshots"
        }

        guard let volumeChildren = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return visibleMountedURLs
        }

        return visibleMountedURLs + volumeChildren.filter { $0.lastPathComponent != "com.apple.TimeMachine.localsnapshots" }
    }

    private static func cloudStorageURLs() -> [URL] {
        let home = realHomeDirectory()
        let mobileDocuments = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Mobile Documents")
        let cloudDocs = mobileDocuments
            .appendingPathComponent("com~apple~CloudDocs")
        let cloudStorage = home
            .appendingPathComponent("Library")
            .appendingPathComponent("CloudStorage")

        var urls = [
            mobileDocuments,
            cloudDocs,
            cloudStorage
        ]
        urls.append(contentsOf: directoryChildren(of: mobileDocuments))
        urls.append(contentsOf: directoryChildren(of: cloudStorage))

        // Finder can hand extensions the firmlinked /System/Volumes/Data form for iCloud paths.
        let dataVolumeVariants = urls.compactMap { dataVolumeVariant(for: $0) }
        return urls + dataVolumeVariants
    }

    private static func finderSyncRootCoverageURLs() -> [URL] {
        let home = realHomeDirectory()
        var urls = [
            home,
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Downloads"),
            URL(fileURLWithPath: "/Users"),
            URL(fileURLWithPath: "/System/Volumes/Data"),
            URL(fileURLWithPath: "/System/Volumes/Data/Users")
        ]
        urls.append(contentsOf: urls.compactMap { dataVolumeVariant(for: $0) })
        return urls
    }

    private static func isRootCoverageRequest(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path == "/" || path == "/System/Volumes/Data"
    }

    private static func directoryChildren(of url: URL) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.filter { child in
            (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private static func dataVolumeVariant(for url: URL) -> URL? {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix("/"), !path.hasPrefix("/System/Volumes/Data/") else { return nil }
        return URL(fileURLWithPath: "/System/Volumes/Data" + path)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique: [URL] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path) else { continue }
            guard seen.insert(standardized.path).inserted else { continue }
            unique.append(standardized)
        }

        return unique
    }

    private static func realHomeDirectory() -> URL {
        if let passwd = getpwuid(getuid()),
           let homePath = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homePath))
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }
}
