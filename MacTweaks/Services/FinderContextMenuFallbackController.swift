import AppKit
import ApplicationServices
import CoreGraphics
import os

final class FinderContextMenuFallbackController: NSObject {
    private let settings: SharedSettingsStore
    private let logger = Logger(subsystem: "com.noah.MacTweaks", category: "FinderContextMenuFallback")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingMouseLocation: CGPoint?
    private var fallbackMenu: NSMenu?
    private var activeContext: FinderMenuContext?

    init(settings: SharedSettingsStore) {
        self.settings = settings
        super.init()
    }

    func refresh() {
        guard settings.masterEnabled,
              settings.enhancedFinderMenusEnabled,
              hasEnabledFinderAction,
              KeyboardDeleteController.isAccessibilityTrusted else {
            stop()
            return
        }
        start()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        pendingMouseLocation = nil
        fallbackMenu?.cancelTracking()
        fallbackMenu = nil
        activeContext = nil
    }

    private func start() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            // Let mouse remappers observe or rewrite right-clicks before this fallback suppresses Finder's menu.
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: finderContextMenuEventTapCallback,
            userInfo: userInfo
        ) else {
            logger.error("Could not create Finder compatibility right-click event tap. Accessibility: \(KeyboardDeleteController.isAccessibilityTrusted, privacy: .public)")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Finder compatibility right-click event tap started")
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .rightMouseUp {
            guard let mouseLocation = pendingMouseLocation else {
                return Unmanaged.passUnretained(event)
            }

            pendingMouseLocation = nil
            DispatchQueue.main.async { [weak self] in
                self?.resolveAndShowFallbackMenu(mouseLocation: mouseLocation)
            }
            return nil
        }

        if type == .rightMouseDown {
            guard shouldHandleRightClick(event: event) else {
                return Unmanaged.passUnretained(event)
            }

            pendingMouseLocation = event.location
            logger.info("Finder compatibility right-click captured at x=\(event.location.x, privacy: .public) y=\(event.location.y, privacy: .public)")
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func shouldHandleRightClick(event: CGEvent) -> Bool {
        guard settings.masterEnabled,
              settings.enhancedFinderMenusEnabled,
              hasEnabledFinderAction else {
            return false
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return false }

        let flags = event.flags
        guard flags.contains(.maskAlternate) else { return false }
        return flags.intersection([.maskCommand, .maskControl]).isEmpty
    }

    private func resolveAndShowFallbackMenu(mouseLocation: CGPoint) {
        guard let context = finderContext(includeSelection: true, mouseLocation: mouseLocation) else {
            logger.error("Finder compatibility menu could not resolve Finder context")
            NSSound.beep()
            return
        }

        logger.info("Resolved Finder compatibility context: \(context.diagnosticSummary, privacy: .public)")
        showFallbackMenu(for: context)
    }

    private func showFallbackMenu(for context: FinderMenuContext) {
        let snapshot = settings.currentSnapshot
        let menu = NSMenu(title: "Mac Tweaks")
        menu.autoenablesItems = false

        for action in FinderMenuAction.enabledActions(settings: snapshot) {
            let item = NSMenuItem(title: action.title(settings: snapshot), action: selector(for: action), keyEquivalent: "")
            item.target = self
            item.representedObject = context
            item.isEnabled = FinderMenuActionExecutor.canPerform(action, context: context, settings: snapshot)
            menu.addItem(item)
        }

        guard !menu.items.isEmpty else {
            return
        }

        logger.info("Showing Finder compatibility menu: \(context.diagnosticSummary, privacy: .public)")
        fallbackMenu?.cancelTracking()
        fallbackMenu = menu
        activeContext = context
        menu.delegate = self
        let popupLocation = NSEvent.mouseLocation
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self, weak menu] in
            guard let self, let menu, self.fallbackMenu === menu else { return }
            _ = menu.popUp(positioning: nil, at: popupLocation, in: nil)
        }
    }

    @objc private func createNewFileHere(_ sender: NSMenuItem) {
        execute(.createNewFileHere, sender: sender)
    }

    @objc private func openInIDE(_ sender: NSMenuItem) {
        execute(.openInIDE, sender: sender)
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        execute(.copyPath, sender: sender)
    }

    @objc private func openTerminalHere(_ sender: NSMenuItem) {
        execute(.openTerminalHere, sender: sender)
    }

    private var hasEnabledFinderAction: Bool {
        settings.createFileEnabled
            || settings.openInIDEEnabled
            || settings.copyPathEnabled
            || settings.openTerminalEnabled
    }

    private func selector(for action: FinderMenuAction) -> Selector {
        switch action {
        case .createNewFileHere:
            return #selector(createNewFileHere(_:))
        case .openInIDE:
            return #selector(openInIDE(_:))
        case .copyPath:
            return #selector(copyPath(_:))
        case .openTerminalHere:
            return #selector(openTerminalHere(_:))
        }
    }

    private func execute(_ action: FinderMenuAction, sender: NSMenuItem) {
        guard let context = (sender.representedObject as? FinderMenuContext) ?? activeContext else {
            NSSound.beep()
            return
        }

        let snapshot = settings.currentSnapshot
        let result = FinderMenuActionExecutor.execute(action, context: context.refreshing(settings: snapshot), settings: snapshot)
        switch result {
        case .success(let executionResult):
            logger.info("Finder fallback action succeeded: \(executionResult.diagnosticSummary, privacy: .public) \(context.diagnosticSummary, privacy: .public)")
        case .failure(let error):
            logger.error("Finder fallback action failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func finderContext(includeSelection: Bool, mouseLocation: CGPoint) -> FinderMenuContext? {
        let selectionScript = includeSelection ? """
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
        """ : ""

        let source = """
        set pathLines to {}
        tell application "Finder"
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
            set end of pathLines to folderPath
        \(selectionScript)
        end tell
        set AppleScript's text item delimiters to linefeed
        return pathLines as text
        """

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            logger.error("Finder context AppleScript failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        let paths = result.stringValue?
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
        guard let currentFolderPath = paths.first else { return nil }

        return FinderMenuContext.compatibilityFallback(
            currentFolderURL: url(fromFinderLocation: currentFolderPath),
            clickedItemURL: finderItemURL(at: mouseLocation),
            selectedURLs: Array(paths.dropFirst()).map { url(fromFinderLocation: $0) },
            settings: settings.currentSnapshot
        )
    }

    private func finderItemURL(at mouseLocation: CGPoint) -> URL? {
        guard let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == "com.apple.finder" else {
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

    private func finderItemURL(from element: AXUIElement) -> URL? {
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

    private func accessibilityURL(from element: AXUIElement) -> URL? {
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

    private func url(fromAccessibilityValue value: CFTypeRef) -> URL? {
        if let url = value as? URL {
            return url.standardizedFileURL
        }

        if let string = value as? String {
            return url(fromFinderLocation: string)
        }

        return nil
    }

    private func url(fromFinderLocation location: String) -> URL {
        if let url = URL(string: location), url.isFileURL {
            return url.standardizedFileURL
        }

        return URL(fileURLWithPath: location).standardizedFileURL
    }

    private func uniquePoints(_ points: [CGPoint]) -> [CGPoint] {
        var seen = Set<String>()
        return points.filter { point in
            seen.insert("\(point.x),\(point.y)").inserted
        }
    }

    private func shouldUseURLAsFinderItem(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard !path.isEmpty else { return false }
        guard FileManager.default.fileExists(atPath: path) else { return false }
        guard path != "/" && path != "/Volumes" else { return false }
        return true
    }
}

extension FinderContextMenuFallbackController: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        if fallbackMenu === menu {
            fallbackMenu = nil
            activeContext = nil
        }
    }
}

private let finderContextMenuEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let controller = Unmanaged<FinderContextMenuFallbackController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handleEvent(type: type, event: event)
}
