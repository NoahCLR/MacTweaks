import ApplicationServices
import Combine
import CoreGraphics
import os

/// The app's two system privacy permissions in one place. Mac Tweaks creates
/// modifying (`.defaultTap`) event taps, so Accessibility is the correct grant for
/// both observing and replacing their events. A separate Input Monitoring grant
/// is only needed by listen-only taps and must not be requested here.
enum Permissions {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Screen Recording is required only for the screen-region OCR capture.
    static var canCaptureScreen: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// `CGRequestScreenCaptureAccess` is the dedicated TCC request: it registers
    /// the app in the privacy pane and shows the system prompt. A ScreenCaptureKit
    /// `SCShareableContent` query is not a substitute — on current macOS it can
    /// fail without ever presenting the prompt. Note macOS shows this prompt only
    /// once per TCC record; after a dismissal the guided flow's "Open Settings"
    /// fallback is the only path.
    static func requestScreenCapturePermission() {
        CGRequestScreenCaptureAccess()
    }
}

struct PermissionSnapshot: Equatable {
    let accessibilityGranted: Bool
    let screenCaptureGranted: Bool

    static var current: PermissionSnapshot {
        PermissionSnapshot(
            accessibilityGranted: Permissions.isAccessibilityTrusted,
            screenCaptureGranted: Permissions.canCaptureScreen
        )
    }
}

enum PermissionOnboardingStep: Hashable {
    case accessibility
    case screenRecording
}

/// Shares permission status and request history across both Settings-window entry
/// points. This coordinator never starts or advances a flow by itself: every TCC
/// request comes from an explicit user action naming exactly one permission.
final class PermissionOnboardingCoordinator: ObservableObject {
    @Published private(set) var snapshot: PermissionSnapshot
    @Published private(set) var requestedSteps = Set<PermissionOnboardingStep>()

    private let logger = Logger(subsystem: "com.ncleroy.MacTweaks", category: "PermissionOnboarding")

    private let readSnapshot: () -> PermissionSnapshot
    private let requestAccessibility: () -> Void
    private let requestScreenCapture: () -> Void

    init(
        readSnapshot: @escaping () -> PermissionSnapshot = { .current },
        requestAccessibility: @escaping () -> Void = Permissions.requestAccessibilityPermission,
        requestScreenCapture: @escaping () -> Void = Permissions.requestScreenCapturePermission
    ) {
        self.readSnapshot = readSnapshot
        self.requestAccessibility = requestAccessibility
        self.requestScreenCapture = requestScreenCapture
        snapshot = readSnapshot()
    }

    func refresh() {
        let latest = readSnapshot()
        if latest != snapshot {
            snapshot = latest
        }
    }

    /// Issues one request only when a user explicitly chooses Continue. Recording
    /// the attempt before crossing into the system API prevents a double-click or
    /// a second Settings window from issuing the same request twice.
    @discardableResult
    func request(_ step: PermissionOnboardingStep) -> Bool {
        refresh()
        guard !isGranted(step) else {
            logger.info("Skipping \(String(describing: step), privacy: .public) request — already granted")
            return false
        }
        guard !requestedSteps.contains(step) else {
            logger.info("Skipping duplicate \(String(describing: step), privacy: .public) request")
            return false
        }

        logger.info("Requesting \(String(describing: step), privacy: .public) permission")
        requestedSteps.insert(step)

        switch step {
        case .accessibility:
            requestAccessibility()
        case .screenRecording:
            requestScreenCapture()
        }
        return true
    }

    func hasRequested(_ step: PermissionOnboardingStep) -> Bool {
        requestedSteps.contains(step)
    }

    private func isGranted(_ step: PermissionOnboardingStep) -> Bool {
        switch step {
        case .accessibility:
            return snapshot.accessibilityGranted
        case .screenRecording:
            return snapshot.screenCaptureGranted
        }
    }
}
