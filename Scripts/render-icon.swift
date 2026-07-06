import AppKit

let size: CGFloat = 1024

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let img = NSImage(size: image.size)
    img.lockFocus()
    image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
    color.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    img.unlockFocus()
    return img
}

// Prepare the tinted glyph before entering the bitmap context.
let config = NSImage.SymbolConfiguration(pointSize: 460, weight: .medium)
guard let rawSymbol = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) else {
    fatalError("symbol unavailable")
}
let glyph = tinted(rawSymbol, .white)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple icon grid: squircle inset ~100 px on a 1024 canvas.
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

// Soft drop shadow under the squircle.
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 22
shadow.set()
NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.19, alpha: 1).setFill()
squircle.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// Vertical gradient fill: lighter slate at top, near-black at bottom.
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1),
    NSColor(calibratedRed: 0.24, green: 0.27, blue: 0.33, alpha: 1),
])!
gradient.draw(in: squircle, angle: 90)

// Subtle top highlight edge.
NSGraphicsContext.current?.saveGraphicsState()
squircle.addClip()
let highlight = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.0),
    NSColor.white.withAlphaComponent(0.12),
])!
highlight.draw(in: NSRect(x: inset, y: rect.maxY - 300, width: rect.width, height: 300), angle: 90)
NSGraphicsContext.current?.restoreGraphicsState()

// Centered glyph.
let gsize = glyph.size
let scale = min(560 / gsize.width, 560 / gsize.height)
let target = NSSize(width: gsize.width * scale, height: gsize.height * scale)
let origin = NSPoint(x: (size - target.width) / 2, y: (size - target.height) / 2)
glyph.draw(in: NSRect(origin: origin, size: target))

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png")
try! png.write(to: out)
print("wrote \(out.path)")
