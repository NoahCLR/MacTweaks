import AppKit
import SwiftUI

/// Bottom-center confirmation toast for OCR to Clipboard: shows what was just copied
/// (or that no text was found) without stealing focus from whatever app the user
/// is working in. A borderless non-activating panel hosting a SwiftUI card —
/// Liquid Glass on macOS 26, material fallback earlier (same pattern as the
/// Settings tab bar). Fades in, auto-dismisses after a few seconds, click to
/// dismiss early. Main-thread only, like the rest of the UI layer.
final class OCRToastPresenter {
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    private let displayDuration: TimeInterval = 4.5
    private let fadeDuration: TimeInterval = 0.18

    func showCopied(_ text: String) {
        show(OCRToastView(
            title: "Copied to Clipboard",
            symbol: "checkmark.circle.fill",
            tint: .green,
            preview: text
        ) { [weak self] in self?.dismiss() })
    }

    func showNoTextFound() {
        show(OCRToastView(
            title: "No Text Found",
            symbol: "text.magnifyingglass",
            tint: .orange,
            preview: nil
        ) { [weak self] in self?.dismiss() })
    }

    private func show<Content: View>(_ content: Content) {
        // A new capture replaces any toast still on screen.
        dismissWorkItem?.cancel()
        panel?.orderOut(nil)

        let hostingView = NSHostingView(rootView: content)
        let size = hostingView.fittingSize
        // The panel is sized once from fittingSize below; the hosting view must
        // not also drive window size through constraints. Left at the default
        // sizing options, NSHostingView in a borderless panel enters a
        // constraint-update feedback loop (windowDidLayout →
        // updateAnimatedWindowSize → needsUpdateConstraints → …) that AppKit
        // detects and crashes on (NSApplication _crashOnException).
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)

        // Plain frame-based container between panel and hosting view, so window
        // layout never negotiates directly with the SwiftUI view's constraints.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = container
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        if let screen = targetScreen() {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + 24
            ))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        let workItem = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: workItem)
    }

    private func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        guard let panel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            if self?.panel === panel { self?.panel = nil }
        })
    }

    /// The toast belongs on the screen the user is looking at — the one holding
    /// the mouse (where the capture selection just happened), not necessarily the
    /// one with the key window.
    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}

private struct OCRToastView: View {
    let title: String
    let symbol: String
    let tint: Color
    let preview: String?
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            if let preview, !preview.isEmpty {
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: 440)
        .modifier(GlassToastBackground())
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onTap)
    }
}

/// Liquid Glass card on macOS 26+, material-filled fallback earlier (the app
/// deploys to macOS 14) — mirrors the Settings tab bar's GlassCapsule.
private struct GlassToastBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
        }
    }
}
