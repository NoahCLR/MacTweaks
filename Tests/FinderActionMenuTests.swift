import XCTest

final class FinderActionMenuTests: XCTestCase {

    // MARK: - Fixtures

    private func snapshot(
        masterEnabled: Bool = true,
        createFileEnabled: Bool = true,
        openInIDEEnabled: Bool = true,
        copyPathEnabled: Bool = true,
        openTerminalEnabled: Bool = true,
        ideApplicationURL: URL? = URL(fileURLWithPath: "/Applications/Fake IDE.app"),
        terminalApplicationURL: URL? = URL(fileURLWithPath: "/Applications/Fake Terminal.app")
    ) -> SettingsSnapshot {
        SettingsSnapshot(
            masterEnabled: masterEnabled,
            createFileEnabled: createFileEnabled,
            openInIDEEnabled: openInIDEEnabled,
            copyPathEnabled: copyPathEnabled,
            openTerminalEnabled: openTerminalEnabled,
            enhancedFinderMenusEnabled: true,
            deleteKeyEnabled: false,
            openContainingFolderForFiles: false,
            ideApplicationURL: ideApplicationURL,
            terminalApplicationURL: terminalApplicationURL,
            finderActionOrder: FinderMenuAction.defaultOrder,
            monitoredFolderURLs: []
        )
    }

    /// A context whose target resolves (a real directory), so eager `canPerform`
    /// sees a resolved target for every action.
    private func resolvedContext(_ settings: SettingsSnapshot) throws -> FinderMenuContext {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return FinderMenuContext.compatibilityFallback(
            currentFolderURL: dir,
            clickedItemURL: dir,
            selectedURLs: [],
            settings: settings
        )
    }

    /// A context with no target — nothing resolves.
    private func unresolvedContext(_ settings: SettingsSnapshot) -> FinderMenuContext {
        FinderMenuContext(
            source: .compatibilityFallback,
            menuKind: .contextualMenuForItems,
            targetedURL: nil,
            selectedURLs: [],
            openContainingFolderForFiles: settings.openContainingFolderForFiles
        )
    }

    // MARK: - Eager (fallback / Services)

    func testEagerEnablesAllWhenResolvedAndAppsPresent() throws {
        let settings = snapshot()
        let context = try resolvedContext(settings)
        for action in FinderMenuAction.allCases {
            XCTAssertTrue(
                FinderActionMenu.isEnabled(action, context: context, snapshot: settings, resolution: .eager),
                "\(action) should be enabled"
            )
        }
    }

    func testEagerDisablesOpenInIDEWhenAppMissing() throws {
        let settings = snapshot(ideApplicationURL: nil)
        let context = try resolvedContext(settings)
        XCTAssertFalse(FinderActionMenu.isEnabled(.openInIDE, context: context, snapshot: settings, resolution: .eager))
        XCTAssertTrue(FinderActionMenu.isEnabled(.copyPath, context: context, snapshot: settings, resolution: .eager))
    }

    func testEagerDisablesEverythingWhenMasterOff() throws {
        let settings = snapshot(masterEnabled: false)
        let context = try resolvedContext(settings)
        for action in FinderMenuAction.allCases {
            XCTAssertFalse(FinderActionMenu.isEnabled(action, context: context, snapshot: settings, resolution: .eager), "\(action)")
        }
    }

    func testEagerDisablesWhenTargetUnresolved() {
        let settings = snapshot()
        let context = unresolvedContext(settings)
        for action in FinderMenuAction.allCases {
            XCTAssertFalse(FinderActionMenu.isEnabled(action, context: context, snapshot: settings, resolution: .eager), "\(action)")
        }
    }

    // MARK: - Lazy (Finder Sync extension)

    func testLazyEnablesCreateAndCopyRegardlessOfTarget() {
        let settings = snapshot()
        let context = unresolvedContext(settings)
        XCTAssertTrue(FinderActionMenu.isEnabled(.createNewFileHere, context: context, snapshot: settings, resolution: .lazy))
        XCTAssertTrue(FinderActionMenu.isEnabled(.copyPath, context: context, snapshot: settings, resolution: .lazy))
    }

    func testLazyGatesAppDependentActionsOnAppPresence() {
        let settings = snapshot()
        let context = unresolvedContext(settings)
        XCTAssertTrue(FinderActionMenu.isEnabled(.openInIDE, context: context, snapshot: settings, resolution: .lazy))
        XCTAssertTrue(FinderActionMenu.isEnabled(.openTerminalHere, context: context, snapshot: settings, resolution: .lazy))

        let missing = snapshot(ideApplicationURL: nil, terminalApplicationURL: nil)
        XCTAssertFalse(FinderActionMenu.isEnabled(.openInIDE, context: context, snapshot: missing, resolution: .lazy))
        XCTAssertFalse(FinderActionMenu.isEnabled(.openTerminalHere, context: context, snapshot: missing, resolution: .lazy))
    }

    func testLazyDisablesEverythingWhenMasterOff() {
        let settings = snapshot(masterEnabled: false)
        let context = unresolvedContext(settings)
        for action in FinderMenuAction.allCases {
            XCTAssertFalse(FinderActionMenu.isEnabled(action, context: context, snapshot: settings, resolution: .lazy), "\(action)")
        }
    }

    // MARK: - The unification

    func testEagerAndLazyDivergeOnUnresolvedTarget() {
        // Same unresolved target: eager gates on hasResolvedTarget (off); lazy does not.
        let settings = snapshot()
        let context = unresolvedContext(settings)
        XCTAssertFalse(FinderActionMenu.isEnabled(.createNewFileHere, context: context, snapshot: settings, resolution: .eager))
        XCTAssertTrue(FinderActionMenu.isEnabled(.createNewFileHere, context: context, snapshot: settings, resolution: .lazy))
    }

    // MARK: - Enabled-action set

    func testEnabledActionsExcludesDisabledAction() {
        let settings = snapshot(copyPathEnabled: false)
        let actions = FinderMenuAction.enabledActions(settings: settings)
        XCTAssertFalse(actions.contains(.copyPath))
        XCTAssertTrue(actions.contains(.createNewFileHere))
    }

    // MARK: - Target/action wiring

    func testBuildMenuTargetsPresenterByDefault() throws {
        let settings = snapshot()
        let context = try resolvedContext(settings)
        let actionMenu = FinderActionMenu(
            snapshot: { settings },
            resolveContext: { _, _, _ in context },
            sink: { _ in }
        )

        let menu = actionMenu.buildMenu(for: context, snapshot: settings, resolution: .eager)

        XCTAssertFalse(menu.items.isEmpty)
        XCTAssertTrue(menu.items.allSatisfy { $0.target === actionMenu })
    }

    func testBuildMenuCanTargetExternalActionReceiver() throws {
        final class ActionTarget: NSObject {}

        let settings = snapshot()
        let context = try resolvedContext(settings)
        let target = ActionTarget()
        let actionMenu = FinderActionMenu(
            snapshot: { settings },
            resolveContext: { _, _, _ in context },
            sink: { _ in }
        )

        let menu = actionMenu.buildMenu(for: context, snapshot: settings, resolution: .lazy, actionTarget: target)

        XCTAssertFalse(menu.items.isEmpty)
        XCTAssertTrue(menu.items.allSatisfy { $0.target === target })
    }
}
