import Foundation
import AppKit

enum FinderActionError: LocalizedError {
    case actionDisabled
    case cannotResolveTargetDirectory
    case cannotCreateFile(URL)
    case cannotCopyPath
    case missingIDEApplication
    case missingTerminalApplication

    var errorDescription: String? {
        switch self {
        case .actionDisabled:
            return "This Finder action is disabled."
        case .cannotResolveTargetDirectory:
            return "Could not determine the Finder location."
        case .cannotCreateFile(let url):
            return "Could not create \(url.lastPathComponent)."
        case .cannotCopyPath:
            return "Could not copy the Finder path."
        case .missingIDEApplication:
            return "No IDE application is configured."
        case .missingTerminalApplication:
            return "No terminal application is configured."
        }
    }
}

enum FinderActionService {
    static func defaultIDEApplicationURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            return url
        }

        let commonPaths = [
            "/Applications/Visual Studio Code.app",
            "/Applications/Visual Studio Code - Insiders.app"
        ]

        return commonPaths
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func defaultTerminalApplicationURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            return url
        }

        let commonPaths = [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app",
            "/Applications/iTerm.app",
            "/Applications/Ghostty.app",
            "/Applications/Warp.app"
        ]

        return commonPaths
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func targetDirectory(clickedURL: URL?, selectedURLs: [URL]) -> URL? {
        if let firstSelection = selectedURLs.first {
            return directoryForActionTarget(firstSelection)
        }

        if let clickedURL {
            return directoryForActionTarget(clickedURL)
        }

        return nil
    }

    static func openTarget(clickedURL: URL?, selectedURLs: [URL], openContainingFolderForFiles: Bool) -> URL? {
        if let firstSelection = selectedURLs.first {
            if openContainingFolderForFiles, !isDirectory(firstSelection) {
                return firstSelection.deletingLastPathComponent()
            }
            return firstSelection
        }

        if let clickedURL {
            if openContainingFolderForFiles, !isDirectory(clickedURL) {
                return clickedURL.deletingLastPathComponent()
            }
            return clickedURL
        }

        return nil
    }

    static func uniqueUntitledFileURL(in directory: URL) -> URL {
        let base = "Untitled"
        let fileExtension = "txt"
        let first = directory.appendingPathComponent("\(base).\(fileExtension)")

        guard FileManager.default.fileExists(atPath: first.path) else {
            return first
        }

        var index = 2
        while true {
            let candidate = directory.appendingPathComponent("\(base) \(index).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    @discardableResult
    static func createUntitledFile(in directory: URL) throws -> URL {
        let fileURL = uniqueUntitledFileURL(in: directory)
        let created = FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        guard created else {
            throw FinderActionError.cannotCreateFile(fileURL)
        }
        return fileURL
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openInIDE(targetURL: URL, ideApplicationURL: URL?) throws {
        guard let ideApplicationURL else {
            throw FinderActionError.missingIDEApplication
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([targetURL], withApplicationAt: ideApplicationURL, configuration: configuration)
    }

    @discardableResult
    static func copyPathsToClipboard(_ urls: [URL]) throws -> URL {
        let standardizedURLs = urls.map(\.standardizedFileURL)
        let paths = standardizedURLs.map(\.path).joined(separator: "\n")
        guard !paths.isEmpty else {
            throw FinderActionError.cannotResolveTargetDirectory
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(paths, forType: .string) else {
            throw FinderActionError.cannotCopyPath
        }
        return standardizedURLs[0]
    }

    static func openTerminal(at directoryURL: URL, terminalApplicationURL: URL?) throws {
        guard let terminalApplicationURL else {
            throw FinderActionError.missingTerminalApplication
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([directoryURL], withApplicationAt: terminalApplicationURL, configuration: configuration)
    }

    private static func directoryForActionTarget(_ url: URL) -> URL {
        isDirectory(url) ? url : url.deletingLastPathComponent()
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
