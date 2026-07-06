import XCTest

final class FinderActionServiceTests: XCTestCase {
    func testUniqueUntitledFileURLUsesBaseNameWhenAvailable() throws {
        let directory = try temporaryDirectory()

        let url = FinderActionService.uniqueUntitledFileURL(in: directory)

        XCTAssertEqual(url.lastPathComponent, "Untitled.txt")
    }

    func testUniqueUntitledFileURLIncrementsWithoutOverwriting() throws {
        let directory = try temporaryDirectory()
        FileManager.default.createFile(atPath: directory.appendingPathComponent("Untitled.txt").path, contents: Data())
        FileManager.default.createFile(atPath: directory.appendingPathComponent("Untitled 2.txt").path, contents: Data())

        let url = FinderActionService.uniqueUntitledFileURL(in: directory)

        XCTAssertEqual(url.lastPathComponent, "Untitled 3.txt")
    }

    func testCreateUntitledFileCreatesEmptyFile() throws {
        let directory = try temporaryDirectory()

        let url = try FinderActionService.createUntitledFile(in: directory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url).count, 0)
    }

    func testTargetDirectoryUsesClickedFolder() throws {
        let directory = try temporaryDirectory()

        let target = FinderActionService.targetDirectory(clickedURL: directory, selectedURLs: [])

        XCTAssertEqual(target?.standardizedFileURL, directory.standardizedFileURL)
    }

    func testTargetDirectoryPrefersSelectedFolderOverClickedParent() throws {
        let parent = try temporaryDirectory()
        let selectedFolder = parent.appendingPathComponent("Selected")
        try FileManager.default.createDirectory(at: selectedFolder, withIntermediateDirectories: true)

        let target = FinderActionService.targetDirectory(clickedURL: parent, selectedURLs: [selectedFolder])

        XCTAssertEqual(target?.standardizedFileURL, selectedFolder.standardizedFileURL)
    }

    func testTargetDirectoryUsesParentForClickedFile() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("Example.swift")
        FileManager.default.createFile(atPath: file.path, contents: Data())

        let target = FinderActionService.targetDirectory(clickedURL: file, selectedURLs: [])

        XCTAssertEqual(target?.standardizedFileURL, directory.standardizedFileURL)
    }

    func testOpenTargetPrefersSelectedFolderOverClickedParent() throws {
        let parent = try temporaryDirectory()
        let selectedFolder = parent.appendingPathComponent("Selected")
        try FileManager.default.createDirectory(at: selectedFolder, withIntermediateDirectories: true)

        let target = FinderActionService.openTarget(
            clickedURL: parent,
            selectedURLs: [selectedFolder],
            openContainingFolderForFiles: false
        )

        XCTAssertEqual(target?.standardizedFileURL, selectedFolder.standardizedFileURL)
    }

    func testOpenTargetCanUseContainingFolderForFiles() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("Example.swift")
        FileManager.default.createFile(atPath: file.path, contents: Data())

        let target = FinderActionService.openTarget(
            clickedURL: file,
            selectedURLs: [],
            openContainingFolderForFiles: true
        )

        XCTAssertEqual(target?.standardizedFileURL, directory.standardizedFileURL)
    }

    func testFinderMenuContextItemRightClickUsesTargetedURLBeforeSelection() throws {
        let parent = try temporaryDirectory()
        let targetedFolder = parent.appendingPathComponent("Targeted")
        let selectedFolder = parent.appendingPathComponent("Selected")
        try FileManager.default.createDirectory(at: targetedFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: selectedFolder, withIntermediateDirectories: true)
        let settings = testSettings()

        let context = FinderMenuContext(
            source: .finderSync,
            menuKind: .contextualMenuForItems,
            targetedURL: targetedFolder,
            selectedURLs: [selectedFolder],
            openContainingFolderForFiles: settings.openContainingFolderForFiles
        )

        XCTAssertEqual(context.createDirectory?.standardizedFileURL, targetedFolder.standardizedFileURL)
        XCTAssertEqual(context.openTarget?.standardizedFileURL, targetedFolder.standardizedFileURL)
        XCTAssertEqual(context.copyPathURLs.map(\.standardizedFileURL), [selectedFolder.standardizedFileURL])
        XCTAssertEqual(context.terminalDirectory?.standardizedFileURL, selectedFolder.standardizedFileURL)
    }

    func testFinderMenuContextContainerUsesTargetedFolderAndIgnoresSelection() throws {
        let parent = try temporaryDirectory()
        let selectedFolder = parent.appendingPathComponent("Selected")
        try FileManager.default.createDirectory(at: selectedFolder, withIntermediateDirectories: true)
        let settings = testSettings()

        let context = FinderMenuContext(
            source: .finderSync,
            menuKind: .contextualMenuForContainer,
            targetedURL: parent,
            selectedURLs: [selectedFolder],
            openContainingFolderForFiles: settings.openContainingFolderForFiles
        )

        XCTAssertEqual(context.createDirectory?.standardizedFileURL, parent.standardizedFileURL)
        XCTAssertEqual(context.openTarget?.standardizedFileURL, parent.standardizedFileURL)
        XCTAssertEqual(context.copyPathURLs.map(\.standardizedFileURL), [parent.standardizedFileURL])
        XCTAssertEqual(context.terminalDirectory?.standardizedFileURL, parent.standardizedFileURL)
    }

    func testFinderMenuContextFileTargetUsesParentForCreateAndOpenContainingFolder() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("Example.swift")
        FileManager.default.createFile(atPath: file.path, contents: Data())

        let context = FinderMenuContext(
            source: .finderSync,
            menuKind: .contextualMenuForItems,
            targetedURL: file,
            selectedURLs: [],
            openContainingFolderForFiles: true
        )

        XCTAssertEqual(context.createDirectory?.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(context.openTarget?.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(context.copyPathURLs.map(\.standardizedFileURL), [file.standardizedFileURL])
        XCTAssertEqual(context.terminalDirectory?.standardizedFileURL, directory.standardizedFileURL)
    }

    func testFinderMenuContextItemMenuFallsBackToSelectionWhenTargetIsMissing() throws {
        let parent = try temporaryDirectory()
        let selectedFolder = parent.appendingPathComponent("Selected")
        try FileManager.default.createDirectory(at: selectedFolder, withIntermediateDirectories: true)
        let settings = testSettings()

        let context = FinderMenuContext(
            source: .finderSync,
            menuKind: .contextualMenuForItems,
            targetedURL: nil,
            selectedURLs: [selectedFolder],
            openContainingFolderForFiles: settings.openContainingFolderForFiles
        )

        XCTAssertEqual(context.createDirectory?.standardizedFileURL, selectedFolder.standardizedFileURL)
        XCTAssertEqual(context.openTarget?.standardizedFileURL, selectedFolder.standardizedFileURL)
        XCTAssertEqual(context.copyPathURLs.map(\.standardizedFileURL), [selectedFolder.standardizedFileURL])
        XCTAssertEqual(context.terminalDirectory?.standardizedFileURL, selectedFolder.standardizedFileURL)
        XCTAssertTrue(FinderMenuActionExecutor.hasResolvedTarget(.createNewFileHere, context: context))
        XCTAssertTrue(FinderMenuActionExecutor.hasResolvedTarget(.openInIDE, context: context))
        XCTAssertTrue(FinderMenuActionExecutor.hasResolvedTarget(.copyPath, context: context))
        XCTAssertTrue(FinderMenuActionExecutor.hasResolvedTarget(.openTerminalHere, context: context))
    }

    func testFinderMenuContextSelectionCopyPathPreservesMultipleURLsWhenTargetIsMissing() throws {
        let parent = try temporaryDirectory()
        let firstFile = parent.appendingPathComponent("One.txt")
        let secondFile = parent.appendingPathComponent("Two.txt")
        FileManager.default.createFile(atPath: firstFile.path, contents: Data())
        FileManager.default.createFile(atPath: secondFile.path, contents: Data())
        let settings = testSettings()

        let context = FinderMenuContext(
            source: .finderSync,
            menuKind: .contextualMenuForItems,
            targetedURL: nil,
            selectedURLs: [firstFile, secondFile],
            openContainingFolderForFiles: settings.openContainingFolderForFiles
        )

        XCTAssertEqual(
            context.copyPathURLs.map(\.standardizedFileURL),
            [firstFile.standardizedFileURL, secondFile.standardizedFileURL]
        )
        XCTAssertEqual(context.terminalDirectory?.standardizedFileURL, parent.standardizedFileURL)
    }

    func testFallbackContextUsesClickedItemBeforeSelection() throws {
        let parent = try temporaryDirectory()
        let clickedFolder = parent.appendingPathComponent("Clicked")
        let selectedFolder = parent.appendingPathComponent("Selected")
        try FileManager.default.createDirectory(at: clickedFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: selectedFolder, withIntermediateDirectories: true)
        let settings = testSettings()

        let context = FinderMenuContext.compatibilityFallback(
            currentFolderURL: parent,
            clickedItemURL: clickedFolder,
            selectedURLs: [selectedFolder],
            settings: settings
        )

        XCTAssertEqual(context.createDirectory?.standardizedFileURL, clickedFolder.standardizedFileURL)
        XCTAssertEqual(context.openTarget?.standardizedFileURL, clickedFolder.standardizedFileURL)
        XCTAssertEqual(context.copyPathURLs.map(\.standardizedFileURL), [clickedFolder.standardizedFileURL])
        XCTAssertEqual(context.terminalDirectory?.standardizedFileURL, clickedFolder.standardizedFileURL)
    }

    func testFinderMenuContextMissingTargetDisablesActions() {
        let settings = testSettings()
        let context = FinderMenuContext(
            source: .finderSync,
            menuKind: .contextualMenuForItems,
            targetedURL: nil,
            selectedURLs: [],
            openContainingFolderForFiles: settings.openContainingFolderForFiles
        )

        XCTAssertFalse(FinderMenuActionExecutor.canPerform(.createNewFileHere, context: context, settings: settings))
        XCTAssertFalse(FinderMenuActionExecutor.canPerform(.openInIDE, context: context, settings: settings))
        XCTAssertFalse(FinderMenuActionExecutor.canPerform(.copyPath, context: context, settings: settings))
        XCTAssertFalse(FinderMenuActionExecutor.canPerform(.openTerminalHere, context: context, settings: settings))
    }

    func testOpenInIDEDisabledWhenIDEIsMissing() throws {
        let directory = try temporaryDirectory()
        let settings = testSettings(ideApplicationURL: nil)
        let context = FinderMenuContext(
            source: .finderSync,
            menuKind: .contextualMenuForItems,
            targetedURL: directory,
            selectedURLs: [],
            openContainingFolderForFiles: settings.openContainingFolderForFiles
        )

        XCTAssertNotNil(context.openTarget)
        XCTAssertFalse(FinderMenuActionExecutor.canPerform(.openInIDE, context: context, settings: settings))
    }

    func testOpenTerminalDisabledWhenTerminalIsMissing() throws {
        let directory = try temporaryDirectory()
        let settings = testSettings(terminalApplicationURL: nil)
        let context = FinderMenuContext(
            source: .finderSync,
            menuKind: .contextualMenuForItems,
            targetedURL: directory,
            selectedURLs: [],
            openContainingFolderForFiles: settings.openContainingFolderForFiles
        )

        XCTAssertNotNil(context.terminalDirectory)
        XCTAssertFalse(FinderMenuActionExecutor.canPerform(.openTerminalHere, context: context, settings: settings))
    }

    func testFinderMenuActionsUseConfiguredOrder() {
        let settings = testSettings(finderActionOrder: [
            .copyPath,
            .openTerminalHere,
            .createNewFileHere,
            .openInIDE
        ])

        XCTAssertEqual(FinderMenuAction.enabledActions(settings: settings), [
            .copyPath,
            .openTerminalHere,
            .createNewFileHere,
            .openInIDE
        ])
    }

    func testFinderMenuActionsSkipDisabledActionsWithoutChangingOrder() {
        let settings = testSettings(
            openInIDEEnabled: false,
            copyPathEnabled: false,
            finderActionOrder: [
                .copyPath,
                .openTerminalHere,
                .openInIDE,
                .createNewFileHere
            ]
        )

        XCTAssertEqual(FinderMenuAction.enabledActions(settings: settings), [
            .openTerminalHere,
            .createNewFileHere
        ])
    }

    func testFinderMenuActionOrderNormalizesStoredValues() {
        let order = FinderMenuAction.normalizedOrder(rawValues: [
            "copyPath",
            "copyPath",
            "missingAction",
            "openInIDE"
        ])

        XCTAssertEqual(order, [
            .copyPath,
            .openInIDE,
            .createNewFileHere,
            .openTerminalHere
        ])
    }

    func testOpenInIDETitleUsesConfiguredAppName() {
        let settings = testSettings(ideApplicationURL: URL(fileURLWithPath: "/Applications/Cursor.app"))

        XCTAssertEqual(FinderMenuAction.openInIDE.title(settings: settings), "Open in Cursor")
    }

    func testOpenTerminalTitleUsesConfiguredAppName() {
        let settings = testSettings(terminalApplicationURL: URL(fileURLWithPath: "/Applications/Warp.app"))

        XCTAssertEqual(FinderMenuAction.openTerminalHere.title(settings: settings), "Open in Warp")
    }

    func testRootMonitoringExpandsToConcreteFinderRoots() {
        let urls = SharedDefaults.expandedMonitoredFolderURLs(basePaths: ["/"])
        let paths = Set(urls.map { $0.standardizedFileURL.path })

        XCTAssertTrue(paths.contains("/"))
        XCTAssertTrue(paths.contains(FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path))
        XCTAssertTrue(paths.contains("/Volumes"))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacTweaksTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func testSettings(
        openContainingFolderForFiles: Bool = false,
        openInIDEEnabled: Bool = true,
        copyPathEnabled: Bool = true,
        ideApplicationURL: URL? = URL(fileURLWithPath: "/Applications/Fake IDE.app"),
        terminalApplicationURL: URL? = URL(fileURLWithPath: "/Applications/Fake Terminal.app"),
        finderActionOrder: [FinderMenuAction] = FinderMenuAction.defaultOrder
    ) -> SettingsSnapshot {
        SettingsSnapshot(
            masterEnabled: true,
            createFileEnabled: true,
            openInIDEEnabled: openInIDEEnabled,
            copyPathEnabled: copyPathEnabled,
            openTerminalEnabled: true,
            enhancedFinderMenusEnabled: true,
            deleteKeyEnabled: false,
            openContainingFolderForFiles: openContainingFolderForFiles,
            ideApplicationURL: ideApplicationURL,
            terminalApplicationURL: terminalApplicationURL,
            finderActionOrder: finderActionOrder,
            monitoredFolderURLs: []
        )
    }
}
