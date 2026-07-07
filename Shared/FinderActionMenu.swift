import AppKit

/// Presents the Finder actions and runs them, owning the AppKit target-action glue
/// that the delivery paths used to each copy: the enabled-actions menu-build loop,
/// the four `@objc` action trampolines, the `selector(for:)` mapping, and the
/// `execute → Result` dispatch.
///
/// A delivery path supplies three things: how to read the current settings
/// snapshot, how to resolve the context to execute for a clicked action (its own
/// click-time logic), and a sink that receives the outcome (so each path keeps its
/// own logging/beep voice). `FinderMenuActionExecutor` stays the pure core behind
/// this glue.
final class FinderActionMenu: NSObject {
    /// How item enable-state is decided at menu-build time.
    /// - `eager`: the target is already resolved, so gate on the full
    ///   `FinderMenuActionExecutor.canPerform` (used by the right-click fallback and
    ///   the Services provider).
    /// - `lazy`: the target is resolved at click time, so gate only on the action's
    ///   app dependency being satisfied (used by the Finder Sync extension).
    enum Resolution {
        case eager
        case lazy
    }

    /// The result of running one action, handed to the sink.
    struct Outcome {
        let action: FinderMenuAction
        let result: Result<FinderMenuActionExecutionResult, Error>
        let context: FinderMenuContext
    }

    /// Resolves the context to execute for a clicked action. Path-specific: the
    /// fallback refreshes its saved/active context; the extension resolves live
    /// Finder state. Returns `nil` when no context can be resolved (the presenter
    /// then beeps, matching prior behavior).
    typealias ContextResolver = (FinderMenuAction, NSMenuItem, SettingsSnapshot) -> FinderMenuContext?
    typealias Sink = (Outcome) -> Void

    private let snapshotProvider: () -> SettingsSnapshot
    private let contextResolver: ContextResolver
    private let sink: Sink

    init(
        snapshot: @escaping () -> SettingsSnapshot,
        resolveContext: @escaping ContextResolver,
        sink: @escaping Sink
    ) {
        self.snapshotProvider = snapshot
        self.contextResolver = resolveContext
        self.sink = sink
        super.init()
    }

    /// Builds a menu of the enabled actions for `context`. The caller owns showing/
    /// tracking the menu.
    ///
    /// `actionTarget` overrides the target/action receiver. In-process callers leave
    /// it nil so items target this presenter directly. The Finder Sync extension
    /// **must** pass its `FIFinderSync` principal object: Finder transports the
    /// returned menu into its own process and only delivers menu-item actions to the
    /// principal object, never to an in-extension helper like this presenter. The
    /// target object must implement the same `@objc` action selectors (see
    /// `selector(for:)`) and forward to `perform`.
    func buildMenu(
        for context: FinderMenuContext,
        snapshot: SettingsSnapshot,
        resolution: Resolution,
        title: String = "",
        actionTarget: AnyObject? = nil
    ) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false

        for action in FinderMenuAction.enabledActions(settings: snapshot) {
            let item = NSMenuItem(title: action.title(settings: snapshot), action: selector(for: action), keyEquivalent: "")
            item.target = actionTarget ?? self
            item.representedObject = context
            item.isEnabled = FinderActionMenu.isEnabled(action, context: context, snapshot: snapshot, resolution: resolution)
            menu.addItem(item)
        }

        return menu
    }

    /// Whether an action's menu item should be enabled at build time. Pure — the
    /// single home for the gate that the fallback (`eager`) and the extension
    /// (`lazy`) used to answer differently.
    static func isEnabled(
        _ action: FinderMenuAction,
        context: FinderMenuContext,
        snapshot: SettingsSnapshot,
        resolution: Resolution
    ) -> Bool {
        switch resolution {
        case .eager:
            return FinderMenuActionExecutor.canPerform(action, context: context, settings: snapshot)
        case .lazy:
            guard snapshot.masterEnabled else { return false }
            switch action {
            case .createNewFileHere, .copyPath:
                return true
            case .openInIDE:
                return snapshot.ideApplicationURL != nil
            case .openTerminalHere:
                return snapshot.terminalApplicationURL != nil
            }
        }
    }

    // MARK: - Target-action glue

    @objc private func createNewFileHere(_ sender: NSMenuItem) { perform(.createNewFileHere, sender: sender) }
    @objc private func openInIDE(_ sender: NSMenuItem) { perform(.openInIDE, sender: sender) }
    @objc private func copyPath(_ sender: NSMenuItem) { perform(.copyPath, sender: sender) }
    @objc private func openTerminalHere(_ sender: NSMenuItem) { perform(.openTerminalHere, sender: sender) }

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

    func perform(_ action: FinderMenuAction, sender: NSMenuItem) {
        let snapshot = snapshotProvider()
        guard let context = contextResolver(action, sender, snapshot) else {
            NSSound.beep()
            return
        }

        sink(FinderActionMenu.run(action, context: context, snapshot: snapshot))
    }

    /// Executes an action against an already-resolved context and packages the
    /// outcome. The shared tail for delivery paths that dispatch outside
    /// target-action (the Services provider builds its own context from the
    /// service pasteboard, then calls this).
    static func run(_ action: FinderMenuAction, context: FinderMenuContext, snapshot: SettingsSnapshot) -> Outcome {
        Outcome(
            action: action,
            result: FinderMenuActionExecutor.execute(action, context: context, settings: snapshot),
            context: context
        )
    }
}
