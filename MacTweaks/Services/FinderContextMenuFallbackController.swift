import AppKit
import CoreGraphics
import os

final class FinderContextMenuFallbackController: NSObject {
    private let settings: SharedSettingsStore
    private let logger = Logger(subsystem: "com.noah.MacTweaks", category: "FinderContextMenuFallback")

    private var pendingMouseLocation: CGPoint?
    private var fallbackMenu: NSMenu?
    private var activeContext: FinderMenuContext?

    // Tail-append so mouse remappers can observe or rewrite right-clicks before
    // this fallback suppresses Finder's native menu.
    private lazy var tap = EventTap(
        eventsOfInterest: (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue),
        place: .tailAppendEventTap
    ) { [weak self] type, event in
        guard let self else { return Unmanaged.passUnretained(event) }
        return self.handle(type: type, event: event)
    }

    // Builds and runs the action menu; the fallback owns showing/tracking it.
    // Click-time context resolution mirrors the old behavior: the item's saved
    // context (or the active one) refreshed against the current snapshot.
    private lazy var actionMenu: FinderActionMenu = {
        let settings = self.settings
        return FinderActionMenu(
            snapshot: { settings.currentSnapshot },
            resolveContext: { [weak self] _, sender, snapshot in
                let base = (sender.representedObject as? FinderMenuContext) ?? self?.activeContext
                return base?.refreshing(settings: snapshot)
            },
            sink: { [weak self] outcome in
                guard let self else { return }
                switch outcome.result {
                case .success(let executionResult):
                    self.logger.info("Finder fallback action succeeded: \(executionResult.diagnosticSummary, privacy: .public) \(outcome.context.diagnosticSummary, privacy: .public)")
                case .failure(let error):
                    self.logger.error("Finder fallback action failed: \(error.localizedDescription, privacy: .public)")
                    NSSound.beep()
                }
            }
        )
    }()

    init(settings: SharedSettingsStore) {
        self.settings = settings
        super.init()
    }

    func refresh() {
        TapGate.reconcile(
            facts: TapGateFacts(
                masterEnabled: settings.masterEnabled,
                featureEnabled: settings.enhancedFinderMenusEnabled && hasEnabledFinderAction,
                accessibilityTrusted: Permissions.isAccessibilityTrusted,
                inputMonitoringGranted: false,
                inputMonitoringAlreadyRequested: false,
                requiresInputMonitoring: false
            ),
            enable: { self.tap.enable() },
            disable: { self.stop() },
            onEnableFailure: {
                self.logger.error("Could not create Finder compatibility right-click event tap. Accessibility: \(Permissions.isAccessibilityTrusted, privacy: .public)")
            }
        )
    }

    func stop() {
        tap.disable()
        pendingMouseLocation = nil
        fallbackMenu?.cancelTracking()
        fallbackMenu = nil
        activeContext = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
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
        guard FinderInputContext.frontmostIsFinder else { return false }

        let flags = event.flags
        guard flags.contains(.maskAlternate) else { return false }
        return flags.intersection([.maskCommand, .maskControl]).isEmpty
    }

    private func resolveAndShowFallbackMenu(mouseLocation: CGPoint) {
        guard let context = finderContext(mouseLocation: mouseLocation) else {
            logger.error("Finder compatibility menu could not resolve Finder context")
            NSSound.beep()
            return
        }

        logger.info("Resolved Finder compatibility context: \(context.diagnosticSummary, privacy: .public)")
        showFallbackMenu(for: context)
    }

    private func showFallbackMenu(for context: FinderMenuContext) {
        let snapshot = settings.currentSnapshot
        let menu = actionMenu.buildMenu(for: context, snapshot: snapshot, resolution: .eager, title: "Mac Tweaks")

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

    private var hasEnabledFinderAction: Bool {
        settings.createFileEnabled
            || settings.openInIDEEnabled
            || settings.copyPathEnabled
            || settings.openTerminalEnabled
    }

    private func finderContext(mouseLocation: CGPoint) -> FinderMenuContext? {
        guard let state = FinderInputContext.currentFolderAndSelection() else { return nil }

        return FinderMenuContext.compatibilityFallback(
            currentFolderURL: state.currentFolderURL,
            clickedItemURL: FinderInputContext.finderItemURL(at: mouseLocation),
            selectedURLs: state.selectionURLs,
            settings: settings.currentSnapshot
        )
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
