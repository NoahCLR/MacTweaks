import AppKit
import ApplicationServices
import CoreGraphics
import os

final class KeyboardDeleteController {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var canListenToInputEvents: Bool {
        CGPreflightListenEventAccess()
    }

    static var hasRequiredPermissions: Bool {
        isAccessibilityTrusted && canListenToInputEvents
    }

    private let settings: SharedSettingsStore
    private let logger = Logger(subsystem: "com.noah.MacTweaks", category: "KeyboardDelete")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var didRequestInputEventAccess = false

    private let backspaceKeyCode: Int64 = 51
    private let forwardDeleteKeyCode: Int64 = 117

    init(settings: SharedSettingsStore) {
        self.settings = settings
    }

    var isRunning: Bool {
        eventTap != nil
    }

    func refresh() {
        guard settings.masterEnabled, settings.deleteKeyEnabled else {
            stop()
            return
        }

        guard Self.isAccessibilityTrusted else {
            stop()
            return
        }

        guard Self.canListenToInputEvents else {
            if !didRequestInputEventAccess {
                didRequestInputEventAccess = true
                if Self.requestInputEventPermission() {
                    start()
                    return
                }
            }
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
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestInputEventPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    private func start() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            logger.error("Could not create keyboard event tap. Accessibility: \(Self.isAccessibilityTrusted, privacy: .public), Input events: \(Self.canListenToInputEvents, privacy: .public)")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Keyboard event tap started")
    }

    fileprivate func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard shouldTransform(event: event) else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [weak self] in
            self?.postFinderMoveToTrashShortcut()
        }
        return nil
    }

    private func shouldTransform(event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == backspaceKeyCode || keyCode == forwardDeleteKeyCode else { return false }

        guard settings.masterEnabled, settings.deleteKeyEnabled else {
            logger.info("Backspace ignored: tweak disabled")
            return false
        }

        let flags = event.flags
        guard flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else {
            logger.info("Backspace ignored: modifier key was held")
            return false
        }

        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            logger.info("Backspace ignored: Finder is not frontmost")
            return false
        }

        guard !isFocusedEditableTextInput() else {
            logger.info("Backspace ignored: editable text input is focused")
            return false
        }

        logger.info("Backspace transformed into Finder Move to Trash")
        return true
    }

    private func isFocusedEditableTextInput() -> Bool {
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

        var editableValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableValue) == .success,
           let editable = editableValue as? Bool {
            return editable
        }

        return role == (kAXTextAreaRole as String) || role == (kAXComboBoxRole as String)
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

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let controller = Unmanaged<KeyboardDeleteController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handleEvent(proxy: proxy, type: type, event: event)
}
