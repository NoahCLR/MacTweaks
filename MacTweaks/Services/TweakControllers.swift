import Foundation

/// The shared shape of a tweak controller: something that owns a live tap and
/// reconciles it against settings + permissions on `refresh()`, and tears it
/// down on `stop()`.
protocol TweakController: AnyObject {
    func refresh()
    func stop()
}

extension KeyboardDeleteController: TweakController {}
extension FinderClipboardController: TweakController {}
extension FinderContextMenuFallbackController: TweakController {}
extension ScreenCaptureOCRController: TweakController {}

/// One handle for the fleet of tap controllers. `AppDelegate` decides *when* to
/// refresh (settings changed, timer tick, permission change); the fleet owns the
/// *fan-out*. A new tweak controller is registered in exactly one place — the
/// `all` array — and then participates in every refresh trigger automatically.
final class TweakControllers {
    let keyboard: KeyboardDeleteController
    let clipboard: FinderClipboardController
    let contextMenuFallback: FinderContextMenuFallbackController
    let screenOCR: ScreenCaptureOCRController

    private let all: [TweakController]

    init(settings: SharedSettingsStore) {
        keyboard = KeyboardDeleteController(settings: settings)
        clipboard = FinderClipboardController(settings: settings)
        contextMenuFallback = FinderContextMenuFallbackController(settings: settings)
        screenOCR = ScreenCaptureOCRController(settings: settings)
        all = [keyboard, clipboard, contextMenuFallback, screenOCR]
    }

    func refreshAll() {
        all.forEach { $0.refresh() }
    }

    func stopAll() {
        all.forEach { $0.stop() }
    }
}
