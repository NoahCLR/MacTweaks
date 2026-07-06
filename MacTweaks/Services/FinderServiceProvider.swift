import AppKit
import os

final class FinderServiceProvider: NSObject {
    private let settings: SharedSettingsStore
    private let logger = Logger(subsystem: "com.noah.MacTweaks", category: "FinderServices")

    init(settings: SharedSettingsStore) {
        self.settings = settings
        super.init()
    }

    @objc(createNewFileHere:userData:error:)
    func createNewFileHere(_ pasteboard: NSPasteboard, userData: String, serviceError: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let snapshot = settings.currentSnapshot
        guard snapshot.masterEnabled, snapshot.createFileEnabled else { return }

        let context = FinderMenuContext.services(selectedURLs: fileURLs(from: pasteboard), settings: snapshot)
        guard context.createDirectory != nil else {
            serviceError.pointee = FinderActionError.cannotResolveTargetDirectory.localizedDescription as NSString
            return
        }

        let result = FinderMenuActionExecutor.execute(.createNewFileHere, context: context, settings: snapshot)
        switch result {
        case .success(let executionResult):
            logger.info("Create New File service succeeded: \(executionResult.diagnosticSummary, privacy: .public) \(context.diagnosticSummary, privacy: .public)")
        case .failure(let error):
            logger.error("Create New File service failed: \(error.localizedDescription, privacy: .public)")
            write(error, to: serviceError)
        }
    }

    @objc(openInIDE:userData:error:)
    func openInIDE(_ pasteboard: NSPasteboard, userData: String, serviceError: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let snapshot = settings.currentSnapshot
        guard snapshot.masterEnabled, snapshot.openInIDEEnabled else { return }

        let context = FinderMenuContext.services(selectedURLs: fileURLs(from: pasteboard), settings: snapshot)
        guard context.openTarget != nil else {
            serviceError.pointee = FinderActionError.cannotResolveTargetDirectory.localizedDescription as NSString
            return
        }

        let result = FinderMenuActionExecutor.execute(.openInIDE, context: context, settings: snapshot)
        switch result {
        case .success(let executionResult):
            logger.info("Open in IDE service succeeded: \(executionResult.diagnosticSummary, privacy: .public) \(context.diagnosticSummary, privacy: .public)")
        case .failure(let error):
            logger.error("Open in IDE service failed: \(error.localizedDescription, privacy: .public)")
            write(error, to: serviceError)
        }
    }

    @objc(copyPath:userData:error:)
    func copyPath(_ pasteboard: NSPasteboard, userData: String, serviceError: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let snapshot = settings.currentSnapshot
        guard snapshot.masterEnabled, snapshot.copyPathEnabled else { return }

        let context = FinderMenuContext.services(selectedURLs: fileURLs(from: pasteboard), settings: snapshot)
        guard !context.copyPathURLs.isEmpty else {
            serviceError.pointee = FinderActionError.cannotResolveTargetDirectory.localizedDescription as NSString
            return
        }

        let result = FinderMenuActionExecutor.execute(.copyPath, context: context, settings: snapshot)
        switch result {
        case .success(let executionResult):
            logger.info("Copy Path service succeeded: \(executionResult.diagnosticSummary, privacy: .public) \(context.diagnosticSummary, privacy: .public)")
        case .failure(let error):
            logger.error("Copy Path service failed: \(error.localizedDescription, privacy: .public)")
            write(error, to: serviceError)
        }
    }

    @objc(openTerminalHere:userData:error:)
    func openTerminalHere(_ pasteboard: NSPasteboard, userData: String, serviceError: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let snapshot = settings.currentSnapshot
        guard snapshot.masterEnabled, snapshot.openTerminalEnabled else { return }

        let context = FinderMenuContext.services(selectedURLs: fileURLs(from: pasteboard), settings: snapshot)
        guard context.terminalDirectory != nil else {
            serviceError.pointee = FinderActionError.cannotResolveTargetDirectory.localizedDescription as NSString
            return
        }

        let result = FinderMenuActionExecutor.execute(.openTerminalHere, context: context, settings: snapshot)
        switch result {
        case .success(let executionResult):
            logger.info("Open Terminal Here service succeeded: \(executionResult.diagnosticSummary, privacy: .public) \(context.diagnosticSummary, privacy: .public)")
        case .failure(let error):
            logger.error("Open Terminal Here service failed: \(error.localizedDescription, privacy: .public)")
            write(error, to: serviceError)
        }
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let fileURLObjects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        let filenameURLs = (pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0) }

        return unique(fileURLObjects + filenameURLs)
    }

    private func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var uniqueURLs: [URL] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            uniqueURLs.append(standardized)
        }

        return uniqueURLs
    }

    private func write(_ serviceError: Error, to pointer: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if let localizedError = serviceError as? LocalizedError,
           let description = localizedError.errorDescription {
            pointer.pointee = description as NSString
        } else {
            pointer.pointee = serviceError.localizedDescription as NSString
        }
    }
}
