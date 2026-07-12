import CoreGraphics
import Foundation

/// A user-configurable keyboard shortcut: a virtual key code plus the set of
/// modifier keys that must be held. Stored in settings as a small plist
/// dictionary (`storedValue`), compared against live `CGEvent`s by `matches`, and
/// rendered for the UI by `displayString`. Pure and testable — see `HotKeyTests`.
struct HotKey: Equatable {
    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int

        static let command = Modifiers(rawValue: 1 << 0)
        static let option  = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift   = Modifiers(rawValue: 1 << 3)

        /// The four modifier keys carried by a live event, ignoring Caps Lock, Fn,
        /// the numeric-pad bit, and the device-dependent left/right variants.
        init(flags: CGEventFlags) {
            var mods: Modifiers = []
            if flags.contains(.maskCommand) { mods.insert(.command) }
            if flags.contains(.maskAlternate) { mods.insert(.option) }
            if flags.contains(.maskControl) { mods.insert(.control) }
            if flags.contains(.maskShift) { mods.insert(.shift) }
            self = mods
        }

        init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    let keyCode: UInt16
    let modifiers: Modifiers

    /// Whether a live key event matches this shortcut. The event flags are masked
    /// to the four modifiers, so Caps Lock / Fn never interfere and the match is
    /// exact (⌘⇧2 does not fire on ⌘⌥⇧2).
    func matches(keyCode eventKeyCode: Int64, flags: CGEventFlags) -> Bool {
        UInt16(truncatingIfNeeded: eventKeyCode) == keyCode
            && Modifiers(flags: flags) == modifiers
    }

    /// Human-readable form in the conventional macOS order: ⌃⌥⇧⌘ then the key.
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        result += HotKey.keyLabel(for: keyCode)
        return result
    }

    // MARK: - Persistence

    /// The plist representation stored in the settings file / defaults suite.
    var storedValue: [String: Int] {
        ["keyCode": Int(keyCode), "modifiers": modifiers.rawValue]
    }

    /// Reconstruct from a stored plist value, tolerating the `NSNumber` boxing a
    /// property list round-trip produces. Returns nil for a missing/garbled value.
    init?(stored: Any?) {
        guard let dict = stored as? [String: Any],
              let code = HotKey.int(dict["keyCode"]) else { return nil }
        self.keyCode = UInt16(truncatingIfNeeded: code)
        self.modifiers = Modifiers(rawValue: HotKey.int(dict["modifiers"]) ?? 0)
    }

    init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        return nil
    }

    // MARK: - Key labels

    /// A subset of the ANSI US virtual-key map — enough to label any shortcut a
    /// user is likely to pick. Unknown codes fall back to a numeric placeholder.
    static func keyLabel(for keyCode: UInt16) -> String {
        keyLabels[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyLabels: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
        9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]

    /// The shipped default: ⌘⇧2 (⌘⇧3/4/5 are taken by macOS's own screenshot tools).
    static let defaultOCRHotKey = HotKey(keyCode: 19, modifiers: [.command, .shift])
}
