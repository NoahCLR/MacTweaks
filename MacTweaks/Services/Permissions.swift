import ApplicationServices
import CoreGraphics

/// The app's system-permission checks and prompts in one place. Accessibility
/// (`AXIsProcessTrusted`) and Input Monitoring (`CGPreflightListenEventAccess`)
/// are distinct TCC permissions; the event-tap controllers gate on both, and the
/// menu bar / Settings surfaces report and request them. Thin by nature — its
/// value is giving a shared concern one home instead of leaking off a controller.
enum Permissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var canListenToInputEvents: Bool {
        CGPreflightListenEventAccess()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestInputEventPermission() -> Bool {
        CGRequestListenEventAccess()
    }
}
