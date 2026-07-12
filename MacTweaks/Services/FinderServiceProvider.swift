import AppKit
import os

final class FinderServiceProvider: NSObject {
    private let settings: SharedSettingsStore
    private let logger = Logger(subsystem: "com.ncleroy.MacTweaks", category: "FinderServices")

    init(settings: SharedSettingsStore) {
        self.settings = settings
        super.init()
    }

    @objc(createNewFileHere:userData:error:)
    func createNewFileHere(_ pasteboard: NSPasteboard, userData: String, serviceError: AutoreleasingUnsafeMutablePointer<NSString?>) {
        perform(.createNewFileHere, from: pasteboard, label: "Create New File", serviceError: serviceError) { $0.createFileEnabled }
    }

    @objc(openInIDE:userData:error:)
    func openInIDE(_ pasteboard: NSPasteboard, userData: String, serviceError: AutoreleasingUnsafeMutablePointer<NSString?>) {
        perform(.openInIDE, from: pasteboard, label: "Open in IDE", serviceError: serviceError) { $0.openInIDEEnabled }
    }

    @objc(copyPath:userData:error:)
    func copyPath(_ pasteboard: NSPasteboard, userData: String, serviceError: AutoreleasingUnsafeMutablePointer<NSString?>) {
        perform(.copyPath, from: pasteboard, label: "Copy Path", serviceError: serviceError) { $0.copyPathEnabled }
    }

    @objc(openTerminalHere:userData:error:)
    func openTerminalHere(_ pasteboard: NSPasteboard, userData: String, serviceError: AutoreleasingUnsafeMutablePointer<NSString?>) {
        perform(.openTerminalHere, from: pasteboard, label: "Open Terminal Here", serviceError: serviceError) { $0.openTerminalEnabled }
    }

    /// Shared tail for the four service entry points: gate, build the services
    /// context from the pasteboard, run via `FinderActionMenu`, and report — logging
    /// success or writing the failure to the service error pointer. The unresolved-
    /// target case falls out of the executor's own guard (same `serviceError` string
    /// as before).
    private func perform(
        _ action: FinderMenuAction,
        from pasteboard: NSPasteboard,
        label: String,
        serviceError: AutoreleasingUnsafeMutablePointer<NSString?>,
        isEnabled: (SettingsSnapshot) -> Bool
    ) {
        let snapshot = settings.currentSnapshot
        guard snapshot.masterEnabled, isEnabled(snapshot) else { return }

        let context = FinderMenuContext.services(selectedURLs: fileURLs(from: pasteboard), settings: snapshot)
        let outcome = FinderActionMenu.run(action, context: context, snapshot: snapshot)
        switch outcome.result {
        case .success(let executionResult):
            logger.info("\(label, privacy: .public) service succeeded: \(executionResult.diagnosticSummary, privacy: .public) \(context.diagnosticSummary, privacy: .public)")
        case .failure(let error):
            logger.error("\(label, privacy: .public) service failed: \(error.localizedDescription, privacy: .public)")
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
