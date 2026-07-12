import CoreGraphics
import XCTest

final class HotKeyTests: XCTestCase {

    // MARK: - Display

    func testDisplayStringUsesConventionalModifierOrder() {
        // ⌘⇧2 — the shipped default. Order is ⌃⌥⇧⌘ then the key.
        XCTAssertEqual(HotKey.defaultOCRHotKey.displayString, "⇧⌘2")
    }

    func testDisplayStringAllModifiers() {
        let hotKey = HotKey(keyCode: 0, modifiers: [.command, .option, .control, .shift])
        XCTAssertEqual(hotKey.displayString, "⌃⌥⇧⌘A")
    }

    func testDisplayStringUnknownKeyFallsBack() {
        XCTAssertEqual(HotKey(keyCode: 200, modifiers: [.command]).displayString, "⌘Key 200")
    }

    // MARK: - Matching

    func testMatchesExactModifiersAndKey() {
        let hotKey = HotKey(keyCode: 19, modifiers: [.command, .shift])
        XCTAssertTrue(hotKey.matches(keyCode: 19, flags: [.maskCommand, .maskShift]))
    }

    func testDoesNotMatchWithExtraModifier() {
        // ⌘⇧2 must not fire on ⌘⌥⇧2 — the modifier set is compared exactly.
        let hotKey = HotKey(keyCode: 19, modifiers: [.command, .shift])
        XCTAssertFalse(hotKey.matches(keyCode: 19, flags: [.maskCommand, .maskShift, .maskAlternate]))
    }

    func testDoesNotMatchDifferentKey() {
        let hotKey = HotKey(keyCode: 19, modifiers: [.command, .shift])
        XCTAssertFalse(hotKey.matches(keyCode: 18, flags: [.maskCommand, .maskShift]))
    }

    func testMatchIgnoresCapsLockAndFn() {
        let hotKey = HotKey(keyCode: 19, modifiers: [.command, .shift])
        let flags: CGEventFlags = [.maskCommand, .maskShift, .maskAlphaShift, .maskSecondaryFn]
        XCTAssertTrue(hotKey.matches(keyCode: 19, flags: flags))
    }

    // MARK: - Persistence round-trip

    func testStoredValueRoundTrips() {
        let hotKey = HotKey(keyCode: 42, modifiers: [.command, .control])
        let restored = HotKey(stored: hotKey.storedValue)
        XCTAssertEqual(restored, hotKey)
    }

    func testStoredValueRoundTripsThroughPropertyListBoxing() {
        // A plist round-trip boxes the Ints as NSNumber — decoding must tolerate it.
        let hotKey = HotKey.defaultOCRHotKey
        let boxed: [String: Any] = [
            "keyCode": NSNumber(value: hotKey.keyCode),
            "modifiers": NSNumber(value: hotKey.modifiers.rawValue)
        ]
        XCTAssertEqual(HotKey(stored: boxed), hotKey)
    }

    func testDecodeRejectsGarbageAndMissingKey() {
        XCTAssertNil(HotKey(stored: nil))
        XCTAssertNil(HotKey(stored: "not a dictionary"))
        XCTAssertNil(HotKey(stored: ["modifiers": 1]))
    }

    // MARK: - OCR text assembly

    func testAssembleTextJoinsAndTrimsLines() {
        let lines = ["  Hello ", "", "   ", "World  "]
        XCTAssertEqual(OCRService.assembleText(from: lines), "Hello\nWorld")
    }

    func testAssembleTextEmptyWhenNothingRecognized() {
        XCTAssertEqual(OCRService.assembleText(from: []), "")
        XCTAssertEqual(OCRService.assembleText(from: ["   ", ""]), "")
    }
}
