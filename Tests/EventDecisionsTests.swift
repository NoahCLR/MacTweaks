import XCTest

final class EventDecisionsTests: XCTestCase {

    // MARK: - Backspace → Move to Trash

    private func backspaceFacts(
        isDeleteKey: Bool = true,
        hasBlockingModifier: Bool = false,
        masterEnabled: Bool = true,
        deleteKeyEnabled: Bool = true,
        frontmostIsFinder: Bool = true,
        isEditableTextFocused: Bool = false
    ) -> BackspaceEventFacts {
        BackspaceEventFacts(
            isDeleteKey: isDeleteKey,
            hasBlockingModifier: hasBlockingModifier,
            masterEnabled: masterEnabled,
            deleteKeyEnabled: deleteKeyEnabled,
            frontmostIsFinder: frontmostIsFinder,
            isEditableTextFocused: isEditableTextFocused
        )
    }

    func testBackspaceInFinderWithTweakOnMovesToTrash() {
        XCTAssertTrue(EventDecision.shouldMoveToTrash(backspaceFacts()))
    }

    func testNonDeleteKeyPassesThrough() {
        XCTAssertFalse(EventDecision.shouldMoveToTrash(backspaceFacts(isDeleteKey: false)))
    }

    func testDeleteWithModifierPassesThrough() {
        XCTAssertFalse(EventDecision.shouldMoveToTrash(backspaceFacts(hasBlockingModifier: true)))
    }

    func testDeleteWhenFinderNotFrontmostPassesThrough() {
        XCTAssertFalse(EventDecision.shouldMoveToTrash(backspaceFacts(frontmostIsFinder: false)))
    }

    func testDeleteWhileEditingTextPassesThrough() {
        XCTAssertFalse(EventDecision.shouldMoveToTrash(backspaceFacts(isEditableTextFocused: true)))
    }

    func testDeleteWithTweakDisabledPassesThrough() {
        XCTAssertFalse(EventDecision.shouldMoveToTrash(backspaceFacts(deleteKeyEnabled: false)))
    }

    func testDeleteWithMasterDisabledPassesThrough() {
        XCTAssertFalse(EventDecision.shouldMoveToTrash(backspaceFacts(masterEnabled: false)))
    }

    // MARK: - Clipboard ⌘X / ⌘V

    private func clipboardFacts(
        key: ClipboardKey = .paste,
        isPlainCommand: Bool = true,
        masterEnabled: Bool = true,
        cutFilesEnabled: Bool = true,
        pasteAsFileEnabled: Bool = true,
        frontmostIsFinder: Bool = true,
        isEditableTextFocused: Bool = false,
        cutPending: Bool = false,
        changeCountMatches: Bool = false,
        hasFileURLs: Bool = false,
        hasQualifyingPayload: Bool = false
    ) -> ClipboardEventFacts {
        ClipboardEventFacts(
            key: key,
            isPlainCommand: isPlainCommand,
            masterEnabled: masterEnabled,
            cutFilesEnabled: cutFilesEnabled,
            pasteAsFileEnabled: pasteAsFileEnabled,
            frontmostIsFinder: { frontmostIsFinder },
            isEditableTextFocused: { isEditableTextFocused },
            cutPending: cutPending,
            changeCountMatches: changeCountMatches,
            hasFileURLs: { hasFileURLs },
            hasQualifyingPayload: { hasQualifyingPayload }
        )
    }

    func testPasteWithLiveCutMovesFiles() {
        let facts = clipboardFacts(key: .paste, cutPending: true, changeCountMatches: true, hasFileURLs: true)
        XCTAssertEqual(EventDecision.clipboard(facts), .move)
    }

    func testPasteWithStaleCutDoesNotMove() {
        // A native ⌘C in between bumped the change count.
        let facts = clipboardFacts(key: .paste, cutPending: true, changeCountMatches: false, hasFileURLs: true)
        XCTAssertEqual(EventDecision.clipboard(facts), .passThrough)
    }

    func testPasteWithCutButNoFileURLsDoesNotMove() {
        let facts = clipboardFacts(key: .paste, cutPending: true, changeCountMatches: true, hasFileURLs: false)
        XCTAssertEqual(EventDecision.clipboard(facts), .passThrough)
    }

    func testPasteWithoutCutWritesQualifyingPayloadAsFile() {
        let facts = clipboardFacts(key: .paste, cutPending: false, hasQualifyingPayload: true)
        XCTAssertEqual(EventDecision.clipboard(facts), .pasteAsFile)
    }

    func testPasteAsFileStillWorksWhenCutTweakOff() {
        let facts = clipboardFacts(key: .paste, cutFilesEnabled: false, hasQualifyingPayload: true)
        XCTAssertEqual(EventDecision.clipboard(facts), .pasteAsFile)
    }

    func testPasteWithPasteAsFileOffPassesThrough() {
        let facts = clipboardFacts(key: .paste, pasteAsFileEnabled: false, hasQualifyingPayload: true)
        XCTAssertEqual(EventDecision.clipboard(facts), .passThrough)
    }

    func testMoveTakesPrecedenceOverPasteAsFile() {
        let facts = clipboardFacts(
            key: .paste, cutPending: true, changeCountMatches: true,
            hasFileURLs: true, hasQualifyingPayload: true
        )
        XCTAssertEqual(EventDecision.clipboard(facts), .move)
    }

    func testCutWithTweakOnMarksCut() {
        XCTAssertEqual(EventDecision.clipboard(clipboardFacts(key: .cut)), .cut)
    }

    func testCutWithTweakOffPassesThrough() {
        XCTAssertEqual(EventDecision.clipboard(clipboardFacts(key: .cut, cutFilesEnabled: false)), .passThrough)
    }

    func testCutWhileEditingTextPassesThrough() {
        // Native text cut in a rename/search field is preserved.
        XCTAssertEqual(EventDecision.clipboard(clipboardFacts(key: .cut, isEditableTextFocused: true)), .passThrough)
    }

    func testNonPlainCommandPassesThrough() {
        // ⌘⌥V (Move Item Here), ⌘⇧V (paste & match style), autorepeat, etc.
        let facts = clipboardFacts(key: .paste, isPlainCommand: false, cutPending: true, changeCountMatches: true, hasFileURLs: true)
        XCTAssertEqual(EventDecision.clipboard(facts), .passThrough)
    }

    func testClipboardWhenFinderNotFrontmostPassesThrough() {
        let facts = clipboardFacts(key: .paste, frontmostIsFinder: false, cutPending: true, changeCountMatches: true, hasFileURLs: true)
        XCTAssertEqual(EventDecision.clipboard(facts), .passThrough)
    }

    func testClipboardWithMasterDisabledPassesThrough() {
        let facts = clipboardFacts(key: .cut, masterEnabled: false)
        XCTAssertEqual(EventDecision.clipboard(facts), .passThrough)
    }
}
