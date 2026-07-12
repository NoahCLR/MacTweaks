import AppKit
import CoreGraphics
import Foundation
import os

/// Owns the single ⌘V/⌘X keyDown tap used while Finder is frontmost. Two
/// behaviors share this tap so precedence is deterministic:
///
/// 1. **Cut & paste files (Windows-style move)** — ⌘X records the current Finder
///    selection onto the pasteboard and marks it "cut"; a following plain ⌘V asks
///    Finder to *move* those files into the current folder (via AppleScript, so the
///    move is undoable and Finder owns permissions/collisions/cross-volume).
/// 2. **Paste clipboard as a file** — when the clipboard holds raw image/text
///    (not file references), ⌘V writes it to a file in the current folder.
///
/// A pending cut only turns ⌘V into a move while it is still the live clipboard:
/// the pasteboard `changeCount` recorded at ⌘X must be unchanged and the pasteboard
/// must still hold file URLs. Any native ⌘C (or a fresh ⌘X) bumps the count and
/// strands the old flag, so "last cut-or-copy wins" falls out for free — and a
/// foreign app writing file URLs can never turn into one of our moves.
final class FinderClipboardController {
    private let settings: SharedSettingsStore
    private let logger = Logger(subsystem: "com.ncleroy.MacTweaks", category: "FinderClipboard")

    private let vKeyCode: Int64 = 9
    private let xKeyCode: Int64 = 7

    /// Set on ⌘X, cleared on a successful move. Only meaningful together with
    /// `cutChangeCount` — see the type doc.
    private var cutPending = false
    private var cutChangeCount = 0

    private lazy var tap = EventTap(
        eventsOfInterest: 1 << CGEventType.keyDown.rawValue
    ) { [weak self] _, event in
        guard let self else { return Unmanaged.passUnretained(event) }
        return self.handle(event: event)
    }

    init(settings: SharedSettingsStore) {
        self.settings = settings
    }

    var isRunning: Bool {
        tap.isRunning
    }

    private var pasteAsFileEnabled: Bool {
        settings.clipboardToFileEnabled && (settings.pasteImageAsFile || settings.pasteTextAsFile)
    }

    func refresh() {
        TapGate.reconcile(
            facts: TapGateFacts(
                masterEnabled: settings.masterEnabled,
                featureEnabled: pasteAsFileEnabled || settings.cutFilesEnabled,
                accessibilityTrusted: Permissions.isAccessibilityTrusted
            ),
            tap: tap,
            onEnableFailure: {
                self.logger.error("Finder clipboard event tap could not start. Accessibility: \(Permissions.isAccessibilityTrusted, privacy: .public)")
            }
        )
    }

    func stop() {
        tap.disable()
    }

    // MARK: - Event handling

    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case xKeyCode:
            return handleCut(event: event)
        case vKeyCode:
            return handlePaste(event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Builds the decision facts from a live event and current state. The Finder
    /// focus and pasteboard reads are lazy, so a ⌘V that can't be ours never runs
    /// an Accessibility query or reads clipboard image/text.
    private func facts(key: ClipboardKey, event: CGEvent, payload: (() -> ClipboardPayload?)? = nil) -> ClipboardEventFacts {
        ClipboardEventFacts(
            key: key,
            isPlainCommand: isPlainCommand(event),
            masterEnabled: settings.masterEnabled,
            cutFilesEnabled: settings.cutFilesEnabled,
            pasteAsFileEnabled: pasteAsFileEnabled,
            frontmostIsFinder: { FinderInputContext.frontmostIsFinder },
            isEditableTextFocused: { FinderInputContext.isFocusedEditableTextInput() },
            cutPending: cutPending,
            changeCountMatches: NSPasteboard.general.changeCount == cutChangeCount,
            hasFileURLs: { [weak self] in self?.pasteboardHasFileURLs() ?? false },
            hasQualifyingPayload: { (payload?() ?? nil) != nil }
        )
    }

    // MARK: - ⌘X (cut)

    private func handleCut(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard EventDecision.clipboard(facts(key: .cut, event: event)) == .cut else {
            return Unmanaged.passUnretained(event)
        }
        DispatchQueue.main.async { [weak self] in
            self?.captureCut()
        }
        return nil
    }

    /// Reads Finder's selection (async — AppleScript can't run inside the tap) and,
    /// when non-empty, writes those file URLs to the pasteboard and marks them cut.
    /// An empty selection is a silent no-op: native ⌘X did nothing there either, and
    /// any earlier pending cut is left untouched.
    private func captureCut() {
        let paths = FinderInputContext.selectionPaths()
        guard !paths.isEmpty else {
            logger.info("⌘X ignored: no Finder selection")
            return
        }

        let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects(urls) else {
            logger.error("⌘X could not write \(urls.count) file URL(s) to the pasteboard")
            return
        }
        cutChangeCount = pasteboard.changeCount
        cutPending = true
        logger.info("Marked \(urls.count) item(s) as cut")
    }

    // MARK: - ⌘V (move or paste-as-file)

    private func handlePaste(event: CGEvent) -> Unmanaged<CGEvent>? {
        let payload = {
            ClipboardPayload.current(imageEnabled: self.settings.pasteImageAsFile,
                                     textEnabled: self.settings.pasteTextAsFile)
        }

        switch EventDecision.clipboard(facts(key: .paste, event: event, payload: payload)) {
        case .move:
            logger.info("Intercepting ⌘V to move cut items")
            DispatchQueue.main.async { [weak self] in
                self?.performMove()
            }
            return nil

        case .pasteAsFile:
            guard let resolved = payload() else { return Unmanaged.passUnretained(event) }
            logger.info("Intercepting ⌘V to write clipboard \(resolved.kindDescription, privacy: .public)")
            DispatchQueue.main.async { [weak self] in
                self?.materialize(resolved)
            }
            return nil

        case .cut, .passThrough:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Whether the pasteboard currently holds file URLs. The cut-validity gating
    /// (flag + change count) is the decision's job; this only reports the URLs.
    private func pasteboardHasFileURLs() -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.isEmpty == false
    }

    /// Triggers Finder's native "Move Item Here" (⌘⌥V) on the files ⌘X placed on
    /// the pasteboard. We synthesize the keystroke rather than scripting Finder's
    /// `move` verb because only Finder's *own* paste command registers on its undo
    /// stack — an AppleScript-driven move is not undoable (⌘Z does nothing). Finder
    /// pastes into its current folder, selects the moved items, and owns
    /// permissions, collisions, trash-on-overwrite, and cross-volume behavior.
    ///
    /// Requires Finder frontmost (already checked) and nothing else intercepting
    /// ⌘⌥V (e.g. a key remapper). The synthetic event carries ⌥, so it passes back
    /// through our own tap as a non-plain ⌘V and is never re-handled.
    private func performMove() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(vKeyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(vKeyCode), keyDown: false) else {
            logger.error("Cut/paste move failed: could not synthesize ⌘⌥V")
            NSSound.beep()
            return
        }

        let flags: CGEventFlags = [.maskCommand, .maskAlternate]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        // One-shot: consume our cut marker. Finder keeps the pasteboard (a native
        // paste doesn't clear it), so a stray extra ⌘V just copies rather than moves.
        cutPending = false
        logger.info("Synthesized ⌘⌥V (Move Item Here) for cut items")
    }

    private func materialize(_ payload: ClipboardPayload) {
        guard let directory = FinderInputContext.insertionLocationURL() else {
            logger.error("Clipboard paste failed: could not resolve Finder folder")
            NSSound.beep()
            return
        }

        let fileURL = FinderClipboardController.uniqueFileURL(
            in: directory,
            baseName: payload.baseName,
            fileExtension: payload.fileExtension
        )

        do {
            try payload.data.write(to: fileURL, options: .atomic)
            logger.info("Wrote clipboard file: \(fileURL.lastPathComponent, privacy: .public)")
            // Select in place rather than NSWorkspace reveal: the file was written
            // into the current Finder location, and reveal opens a new window for a
            // Desktop item even though the user is already looking at it. On the
            // Desktop, skip selection entirely — the file is already visible there,
            // and Finder's `select` command would itself pop a new window.
            if !FinderInputContext.isDesktopFolder(directory) {
                FinderInputContext.selectInFinder(fileURL)
            }
        } catch {
            logger.error("Clipboard paste failed writing \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    /// Plain ⌘-modified keystroke — no ⇧/⌃/⌥ and not an autorepeat. Leaves
    /// ⌘⇧V (paste and match style), ⌘⌥V (move item here), etc. to the system.
    private func isPlainCommand(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
        let flags = event.flags
        guard flags.contains(.maskCommand) else { return false }
        return flags.intersection([.maskShift, .maskControl, .maskAlternate]).isEmpty
    }

    static func uniqueFileURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
        let first = directory.appendingPathComponent("\(baseName).\(fileExtension)")
        guard FileManager.default.fileExists(atPath: first.path) else { return first }

        var index = 2
        while true {
            let candidate = directory.appendingPathComponent("\(baseName) \(index).\(fileExtension)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
