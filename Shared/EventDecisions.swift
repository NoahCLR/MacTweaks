import Foundation

/// Pure decision logic for the Finder-scoped keyboard tweaks. The controllers
/// extract these facts from a live `CGEvent` plus system state, then call in
/// here — so the interesting behavior (what a keystroke should do) is a pure
/// function testable without an event tap. See `EventDecisionsTests`.

/// Everything the Backspace/Forward-Delete → Move-to-Trash decision depends on.
struct BackspaceEventFacts {
    /// The key is Backspace or Forward-Delete (not some other key).
    let isDeleteKey: Bool
    /// A ⌘/⌃/⌥ modifier was held (Backspace-to-Trash requires none).
    let hasBlockingModifier: Bool
    let masterEnabled: Bool
    let deleteKeyEnabled: Bool
    let frontmostIsFinder: Bool
    /// A rename field or other editable text control has focus.
    let isEditableTextFocused: Bool
}

/// What a ⌘X / ⌘V keystroke should do while Finder is frontmost.
enum ClipboardAction: Equatable {
    /// Leave the keystroke to the system (native copy-paste, text edit, etc.).
    case passThrough
    /// ⌘X: mark the Finder selection as cut.
    case cut
    /// ⌘V: move the cut files into the current folder (Windows-style).
    case move
    /// ⌘V: write raw clipboard image/text to a file in the current folder.
    case pasteAsFile
}

/// The key a clipboard keystroke represents.
enum ClipboardKey {
    case cut     // ⌘X
    case paste   // ⌘V
    case other
}

/// Everything the ⌘X / ⌘V decision depends on. The two pasteboard predicates are
/// closures so the caller keeps its lazy reads — they are only evaluated once the
/// cheap gates pass, matching the live handler's behavior inside the event tap.
struct ClipboardEventFacts {
    let key: ClipboardKey
    /// ⌘ held with no ⇧/⌃/⌥, and not an autorepeat.
    let isPlainCommand: Bool
    let masterEnabled: Bool
    let cutFilesEnabled: Bool
    let pasteAsFileEnabled: Bool
    /// Finder is the frontmost app. Lazy so a non-Finder-relevant keystroke
    /// (e.g. autorepeat ⌘V) never pays for the lookup.
    let frontmostIsFinder: () -> Bool
    /// A rename/search field has focus (Accessibility round-trip — kept lazy).
    let isEditableTextFocused: () -> Bool
    /// A cut is pending (set by a prior ⌘X).
    let cutPending: Bool
    /// The pasteboard is unchanged since the ⌘X that set the cut.
    let changeCountMatches: Bool
    /// The pasteboard currently holds file URLs.
    let hasFileURLs: () -> Bool
    /// The clipboard holds raw image/text eligible to become a file.
    let hasQualifyingPayload: () -> Bool
}

enum EventDecision {
    /// Decides what a ⌘X / ⌘V keystroke should do. Pure — see `ClipboardEventFacts`.
    static func clipboard(_ facts: ClipboardEventFacts) -> ClipboardAction {
        // Cheap gates first; the Finder-focus lookups (below) stay unevaluated
        // for keystrokes that can't be ours.
        guard facts.masterEnabled, facts.isPlainCommand else { return .passThrough }
        guard facts.key != .other else { return .passThrough }
        guard facts.frontmostIsFinder(), !facts.isEditableTextFocused() else { return .passThrough }

        switch facts.key {
        case .cut:
            return facts.cutFilesEnabled ? .cut : .passThrough

        case .paste:
            // Move wins, but only while our cut is still the live clipboard.
            if facts.cutFilesEnabled,
               facts.cutPending,
               facts.changeCountMatches,
               facts.hasFileURLs() {
                return .move
            }
            // Otherwise raw image/text becomes a file (never file references).
            if facts.pasteAsFileEnabled, facts.hasQualifyingPayload() {
                return .pasteAsFile
            }
            return .passThrough

        case .other:
            return .passThrough
        }
    }

    /// True when the keystroke should be transformed into Finder's Move-to-Trash.
    static func shouldMoveToTrash(_ facts: BackspaceEventFacts) -> Bool {
        facts.isDeleteKey
            && facts.masterEnabled
            && facts.deleteKeyEnabled
            && !facts.hasBlockingModifier
            && facts.frontmostIsFinder
            && !facts.isEditableTextFocused
    }
}
