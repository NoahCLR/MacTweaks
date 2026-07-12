import AppKit
import CoreGraphics
import os

/// Owns a global keyDown tap that fires screen-region OCR when the user presses
/// the configured hotkey. Unlike the Finder keyboard tweaks this is *not* scoped
/// to Finder — a screenshot-to-text shortcut should work over any app — so the
/// handler gates only on the hotkey match, not on the frontmost application.
///
/// Reuses the shared tap plumbing and permission gate: the modifying tap needs
/// Accessibility; the capture itself additionally needs Screen Recording, which
/// the guided Permissions tab requests before the first capture.
final class ScreenCaptureOCRController {
    private let settings: SharedSettingsStore
    private let ocrService: OCRService
    private let logger = Logger(subsystem: "com.ncleroy.MacTweaks", category: "ScreenCaptureOCR")

    private lazy var tap = EventTap(
        eventsOfInterest: 1 << CGEventType.keyDown.rawValue
    ) { [weak self] _, event in
        guard let self else { return Unmanaged.passUnretained(event) }
        return self.handle(event: event)
    }

    init(settings: SharedSettingsStore, ocrService: OCRService = OCRService()) {
        self.settings = settings
        self.ocrService = ocrService
    }

    var isRunning: Bool {
        tap.isRunning
    }

    func refresh() {
        TapGate.reconcile(
            facts: TapGateFacts(
                masterEnabled: settings.masterEnabled,
                featureEnabled: settings.ocrEnabled,
                accessibilityTrusted: Permissions.isAccessibilityTrusted
            ),
            tap: tap,
            onEnableFailure: {
                self.logger.error("OCR event tap could not start. Accessibility: \(Permissions.isAccessibilityTrusted, privacy: .public)")
            }
        )
    }

    func stop() {
        tap.disable()
    }

    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Cheap early-out: autorepeat never triggers a capture (one grab per press).
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard settings.masterEnabled,
              settings.ocrEnabled,
              settings.ocrHotKey.matches(keyCode: keyCode, flags: event.flags) else {
            return Unmanaged.passUnretained(event)
        }

        logger.info("OCR hotkey pressed — starting screen capture")
        DispatchQueue.main.async { [weak self] in
            self?.ocrService.captureAndCopy()
        }
        // Swallow the keystroke so the chosen combo doesn't also reach the focused app.
        return nil
    }
}
