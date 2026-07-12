import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

/// Single owner of reads of Finder's live state — frontmost check, editable-focus
/// check, the current folder ("insertion location"), the current selection, and a
/// combined folder+selection snapshot. Kept in one place so every caller (the two
/// keyboard-tap controllers and the right-click fallback) applies identical guards
/// and shares one AppleScript folder-resolution ladder.
///
/// The AppleScript-backed reads run Finder automation, so never call them from
/// inside an event-tap callback — dispatch off the tap thread first.
enum FinderInputContext {
    private static let logger = Logger(subsystem: "com.ncleroy.MacTweaks", category: "FinderInputContext")

    static var frontmostIsFinder: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    /// True when the system-wide focused element is an editable text control
    /// (e.g. a Finder rename field), where ⌘V / Backspace should behave natively.
    static func isFocusedEditableTextInput() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focused = focusedValue else {
            return false
        }

        let element = focused as! AXUIElement
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String else {
            return false
        }

        let textRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ]
        guard textRoles.contains(role) else { return false }

        // A field that explicitly reports itself non-editable (a read-only text
        // control) is not a text-editing context.
        var editableValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableValue) == .success,
           let editable = editableValue as? Bool {
            return editable
        }

        // Otherwise a focused text-input field means the user is typing — e.g. a
        // Finder rename or search field, which doesn't expose AXEditable. Treat it
        // as editable so Backspace/⌘X/⌘V behave natively and never trash a file or
        // paste-as-file mid-edit. (Finder's file list is an outline/table, not a
        // text role, so a plain selection still falls through to `false` above.)
        return true
    }

    /// POSIX paths of the current Finder selection, in order. Returns a list from
    /// AppleScript (never newline-joined text), so filenames containing newlines
    /// stay intact.
    static func selectionPaths() -> [String] {
        let source = """
        tell application "Finder"
            set out to {}
            repeat with anItem in (get selection)
                set end of out to POSIX path of (anItem as alias)
            end repeat
            return out
        end tell
        """

        guard let result = runAppleScript(source, label: "selection") else { return [] }
        guard result.numberOfItems > 0 else { return [] }

        var paths: [String] = []
        for index in 1...result.numberOfItems {
            if let path = result.atIndex(index)?.stringValue, !path.isEmpty {
                paths.append(path)
            }
        }
        return paths
    }

    /// Resolves Finder's paste target ("insertion location") — the front window's
    /// current folder, or the Desktop when no window is targeted. Mirrors where a
    /// native ⌘V would drop pasted items.
    static func insertionLocationURL() -> URL? {
        let source = """
        tell application "Finder"
        \(folderResolutionBody)
            return folderPath
        end tell
        """

        guard let result = runAppleScript(source, label: "insertion-location"),
              let location = result.stringValue, !location.isEmpty else {
            return nil
        }
        return url(fromFinderLocation: location)
    }

    /// The current folder and selection resolved together in one AppleScript
    /// round-trip — the shape the right-click fallback needs. Returns `nil` when the
    /// folder can't be resolved. Reuses the same folder-resolution ladder as
    /// `insertionLocationURL()`.
    static func currentFolderAndSelection() -> FinderSelectionContext? {
        let source = """
        set pathLines to {}
        tell application "Finder"
        \(folderResolutionBody)
            set end of pathLines to folderPath
            repeat with selectedItem in selection
                try
                    set selectedPath to URL of selectedItem as text
                on error
                    try
                        set selectedPath to POSIX path of (selectedItem as alias)
                    on error
                        set selectedPath to ""
                    end try
                end try
                if selectedPath is not "" then
                    set end of pathLines to selectedPath
                end if
            end repeat
        end tell
        set AppleScript's text item delimiters to linefeed
        return pathLines as text
        """

        guard let result = runAppleScript(source, label: "folder+selection") else { return nil }

        let paths = result.stringValue?
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
        guard let folder = paths.first else { return nil }

        return FinderSelectionContext(
            currentFolderURL: url(fromFinderLocation: folder),
            selectionURLs: Array(paths.dropFirst()).map { url(fromFinderLocation: $0) }
        )
    }

    /// Coerces a Finder location string — either a `file://` URL or a POSIX path —
    /// into a standardized file URL.
    static func url(fromFinderLocation location: String) -> URL {
        if let url = URL(string: location), url.isFileURL {
            return url.standardizedFileURL
        }
        return URL(fileURLWithPath: location).standardizedFileURL
    }

    /// Whether `url` is the user's Desktop folder (handling the `/System/Volumes/Data`
    /// firmlink form Finder sometimes reports). Desktop items are already visible
    /// without any window, so callers skip `selectInFinder` for them — Finder's
    /// `select` command pops a new window for a Desktop item when none is open.
    static func isDesktopFolder(_ url: URL) -> Bool {
        guard let desktop = try? FileManager.default.url(
            for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return false }
        return normalizedFolderPath(url) == normalizedFolderPath(desktop)
    }

    private static func normalizedFolderPath(_ url: URL) -> String {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let dataPrefix = "/System/Volumes/Data"
        if path.hasPrefix(dataPrefix) {
            return String(path.dropFirst(dataPrefix.count))
        }
        return path
    }

    /// Selects a file in Finder *in place*, in its containing window. Runs
    /// AppleScript, so call it off the tap thread. Do not call this for a Desktop
    /// item (see `isDesktopFolder`): Finder's `select` opens a new window for one.
    static func selectInFinder(_ url: URL) {
        let source = """
        tell application "Finder"
            activate
            try
                select (POSIX file \(appleScriptStringLiteral(url.path)) as alias)
            end try
        end tell
        """
        _ = runAppleScript(source, label: "select")
    }

    /// A safely-quoted AppleScript string literal (backslash and quote escaped),
    /// so a path containing quotes can't break out of — or inject into — a script.
    static func appleScriptStringLiteral(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // MARK: - Accessibility item-at-point

    /// Resolves the Finder item under a screen point via Accessibility. Tries the
    /// event location and the live cursor location (Finder can report either
    /// coordinate space), climbing each hit's ancestry for a usable file URL.
    /// Requires Finder frontmost. Uses AppKit's `NSEvent.mouseLocation`, so call it
    /// on the main thread.
    static func finderItemURL(at mouseLocation: CGPoint) -> URL? {
        guard frontmostIsFinder,
              let finder = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(finder.processIdentifier)
        let candidatePoints = uniquePoints([mouseLocation, NSEvent.mouseLocation])

        for point in candidatePoints {
            var element: AXUIElement?
            guard AXUIElementCopyElementAtPosition(appElement, Float(point.x), Float(point.y), &element) == .success,
                  let element,
                  let url = finderItemURL(from: element) else {
                continue
            }
            return url
        }

        return nil
    }

    /// Whether a resolved URL is usable as the clicked Finder item: non-empty, on
    /// disk, and not a bare volume root (`/` or `/Volumes`).
    static func shouldUseURLAsFinderItem(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard !path.isEmpty else { return false }
        guard FileManager.default.fileExists(atPath: path) else { return false }
        guard path != "/" && path != "/Volumes" else { return false }
        return true
    }

    private static func finderItemURL(from element: AXUIElement) -> URL? {
        var current: AXUIElement? = element
        var depth = 0

        while let item = current, depth < 8 {
            if let url = accessibilityURL(from: item),
               shouldUseURLAsFinderItem(url) {
                return url
            }

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXParentAttribute as CFString, &parentValue) == .success else {
                break
            }
            guard let parentValue, CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                break
            }
            current = (parentValue as! AXUIElement)
            depth += 1
        }

        return nil
    }

    private static func accessibilityURL(from element: AXUIElement) -> URL? {
        for attribute in ["AXURL", "AXFilename", "AXPath", "AXDocument"] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let value,
                  let url = url(fromAccessibilityValue: value) else {
                continue
            }
            return url
        }

        return nil
    }

    private static func url(fromAccessibilityValue value: CFTypeRef) -> URL? {
        if let url = value as? URL {
            return url.standardizedFileURL
        }

        if let string = value as? String {
            return url(fromFinderLocation: string)
        }

        return nil
    }

    private static func uniquePoints(_ points: [CGPoint]) -> [CGPoint] {
        var seen = Set<String>()
        return points.filter { point in
            seen.insert("\(point.x),\(point.y)").inserted
        }
    }

    // MARK: - AppleScript plumbing

    /// The nested-`try` ladder (insertion location → front window target → desktop,
    /// each with a URL-then-POSIX fallback) that runs inside a `tell application
    /// "Finder"` block and leaves the resolved path in `folderPath`. Shared by
    /// `insertionLocationURL()` and `currentFolderAndSelection()` so the ladder has
    /// one home.
    private static let folderResolutionBody = """
            set folderPath to ""
            try
                try
                    set folderPath to URL of insertion location as text
                on error
                    set folderPath to POSIX path of ((insertion location) as alias)
                end try
            on error
                try
                    if (count of Finder windows) > 0 then
                        try
                            set folderPath to URL of (target of front Finder window) as text
                        on error
                            set folderPath to POSIX path of ((target of front Finder window) as alias)
                        end try
                    else
                        try
                            set folderPath to URL of desktop as text
                        on error
                            set folderPath to POSIX path of (desktop as alias)
                        end try
                    end if
                on error
                    try
                        set folderPath to URL of desktop as text
                    on error
                        set folderPath to POSIX path of (desktop as alias)
                    end try
                end try
            end try
    """

    private static func runAppleScript(_ source: String, label: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            logger.error("Finder \(label, privacy: .public) AppleScript failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        return result
    }
}

/// Finder's current folder plus its selection, resolved together.
struct FinderSelectionContext {
    let currentFolderURL: URL
    let selectionURLs: [URL]
}
