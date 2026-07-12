import AppKit
import SwiftUI

/// A click-to-record keyboard-shortcut field. Idle, it shows the current shortcut;
/// clicked, it listens for the next key combination via a local event monitor
/// (the Settings window is key, so a local monitor sees the keystroke and can
/// swallow it). Esc cancels, ⌫ reverts to the default. A bare key with no
/// ⌘/⌥/⌃ modifier is rejected — a global hotkey needs a modifier to be safe.
struct ShortcutRecorderField: View {
    @Binding var hotKey: HotKey

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 6) {
                Image(systemName: isRecording ? "record.circle" : "keyboard")
                    .foregroundStyle(isRecording ? Color.red : .secondary)
                Text(isRecording ? "Press shortcut…" : hotKey.displayString)
                    .font(.body.monospaced())
                    .foregroundStyle(isRecording ? Color.secondary : .primary)
            }
            .frame(minWidth: 130)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.secondary.opacity(isRecording ? 0.18 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: isRecording ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Click and press a key combination to set the OCR to Clipboard shortcut. Esc cancels, ⌫ resets to the default.")
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil // swallow the keystroke while recording
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        // Esc cancels without changing the shortcut.
        if event.keyCode == 53 {
            stopRecording()
            return
        }
        // ⌫ / ⌦ reverts to the shipped default.
        if event.keyCode == 51 || event.keyCode == 117 {
            hotKey = .defaultOCRHotKey
            stopRecording()
            return
        }

        let modifiers = HotKey.Modifiers(nsFlags: event.modifierFlags)
        // Require a real modifier so the hotkey can't be a bare key that would
        // fire constantly while typing.
        guard modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control) else {
            NSSound.beep()
            return
        }

        hotKey = HotKey(keyCode: event.keyCode, modifiers: modifiers)
        stopRecording()
    }
}

private extension HotKey.Modifiers {
    /// Translate AppKit's modifier flags (from the recorder) into the storage set.
    init(nsFlags: NSEvent.ModifierFlags) {
        var mods: HotKey.Modifiers = []
        if nsFlags.contains(.command) { mods.insert(.command) }
        if nsFlags.contains(.option) { mods.insert(.option) }
        if nsFlags.contains(.control) { mods.insert(.control) }
        if nsFlags.contains(.shift) { mods.insert(.shift) }
        self = mods
    }
}
