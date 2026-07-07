import AppKit
import CoreGraphics
import os

final class KeyboardDeleteController {
    private let settings: SharedSettingsStore
    private let logger = Logger(subsystem: "com.noah.MacTweaks", category: "KeyboardDelete")

    private var didRequestInputEventAccess = false

    private let backspaceKeyCode: Int64 = 51
    private let forwardDeleteKeyCode: Int64 = 117

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

    func refresh() {
        TapGate.reconcile(
            facts: TapGateFacts(
                masterEnabled: settings.masterEnabled,
                featureEnabled: settings.deleteKeyEnabled,
                accessibilityTrusted: Permissions.isAccessibilityTrusted,
                inputMonitoringGranted: Permissions.canListenToInputEvents,
                inputMonitoringAlreadyRequested: didRequestInputEventAccess,
                requiresInputMonitoring: true
            ),
            tap: tap,
            didRequestInput: &didRequestInputEventAccess,
            requestInput: Permissions.requestInputEventPermission,
            onEnableFailure: {
                self.logger.error("Keyboard event tap could not start. Accessibility: \(Permissions.isAccessibilityTrusted, privacy: .public), Input events: \(Permissions.canListenToInputEvents, privacy: .public)")
            }
        )
    }

    func stop() {
        tap.disable()
    }

    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // Cheap early-out so we never run Accessibility queries on every keystroke.
        guard keyCode == backspaceKeyCode || keyCode == forwardDeleteKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let facts = BackspaceEventFacts(
            isDeleteKey: true,
            hasBlockingModifier: !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
            masterEnabled: settings.masterEnabled,
            deleteKeyEnabled: settings.deleteKeyEnabled,
            frontmostIsFinder: FinderInputContext.frontmostIsFinder,
            isEditableTextFocused: FinderInputContext.isFocusedEditableTextInput()
        )

        guard EventDecision.shouldMoveToTrash(facts) else {
            return Unmanaged.passUnretained(event)
        }

        logger.info("Backspace transformed into Finder Move to Trash")
        DispatchQueue.main.async { [weak self] in
            self?.postFinderMoveToTrashShortcut()
        }
        return nil
    }

    private func postFinderMoveToTrashShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(backspaceKeyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(backspaceKeyCode), keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
