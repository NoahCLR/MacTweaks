import AppKit
import Foundation

/// A resolved, ready-to-write clipboard payload. Image is preferred over text when
/// both are present; source image format is preserved (PNG/JPEG) and anything else
/// (e.g. a TIFF-only screenshot) is transcoded to PNG.
///
/// The format *policy* — which representation wins and what file it becomes — is a
/// pure function (`from(...)`) over injected pasteboard facts, so it is testable
/// without a live pasteboard (see `ClipboardPayloadTests`). `current(...)` is the
/// thin adapter that reads `NSPasteboard.general` and calls the policy; it is the
/// only code here that touches the singleton.
struct ClipboardPayload {
    enum Kind {
        case image
        case text
    }

    let kind: Kind
    let data: Data
    let fileExtension: String

    var baseName: String {
        let stamp = ClipboardPayload.timestampFormatter.string(from: Date())
        switch kind {
        case .image:
            return "Pasted Image \(stamp)"
        case .text:
            return "Pasted Text \(stamp)"
        }
    }

    var kindDescription: String {
        "\(kind == .image ? "image" : "text").\(fileExtension)"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    static let jpegType = NSPasteboard.PasteboardType("public.jpeg")

    /// Reads the live general pasteboard and resolves a payload. Thin adapter over
    /// the pure `from(...)` policy — the only pasteboard-singleton read.
    static func current(imageEnabled: Bool, textEnabled: Bool) -> ClipboardPayload? {
        let pasteboard = NSPasteboard.general
        return from(
            types: pasteboard.types ?? [],
            imageEnabled: imageEnabled,
            textEnabled: textEnabled,
            data: { pasteboard.data(forType: $0) },
            string: { pasteboard.string(forType: $0) },
            fallbackImageTIFF: { NSImage(pasteboard: pasteboard)?.tiffRepresentation }
        )
    }

    /// Pure format policy over injected pasteboard facts. Copied files paste
    /// natively (never hijacked); image wins over text; PNG/JPEG pass through and
    /// anything else image-like is transcoded to PNG; RTF→`.rtf`, else plain
    /// text→`.txt`.
    ///
    /// - Parameters:
    ///   - types: the pasteboard's available types.
    ///   - data: reads raw data for a type (as `NSPasteboard.data(forType:)` would).
    ///   - string: reads a string for a type (as `NSPasteboard.string(forType:)` would).
    ///   - fallbackImageTIFF: a TIFF representation for pasteboards that only vend an
    ///     `NSImage`-readable form (defaults to `NSImage(pasteboard:)` in `current`).
    static func from(
        types: [NSPasteboard.PasteboardType],
        imageEnabled: Bool,
        textEnabled: Bool,
        data: (NSPasteboard.PasteboardType) -> Data?,
        string: (NSPasteboard.PasteboardType) -> String?,
        fallbackImageTIFF: () -> Data?
    ) -> ClipboardPayload? {
        // Copied files paste natively — never hijack those.
        let fileReferenceTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ]
        if fileReferenceTypes.contains(where: types.contains) {
            return nil
        }

        if imageEnabled,
           let image = imagePayload(types: types, data: data, fallbackImageTIFF: fallbackImageTIFF) {
            return image
        }

        if textEnabled, let text = textPayload(types: types, data: data, string: string) {
            return text
        }

        return nil
    }

    private static func imagePayload(
        types: [NSPasteboard.PasteboardType],
        data: (NSPasteboard.PasteboardType) -> Data?,
        fallbackImageTIFF: () -> Data?
    ) -> ClipboardPayload? {
        if types.contains(.png), let png = data(.png) {
            return ClipboardPayload(kind: .image, data: png, fileExtension: "png")
        }
        if types.contains(jpegType), let jpeg = data(jpegType) {
            return ClipboardPayload(kind: .image, data: jpeg, fileExtension: "jpg")
        }
        if types.contains(.tiff), let tiff = data(.tiff),
           let png = pngData(fromTIFF: tiff) {
            return ClipboardPayload(kind: .image, data: png, fileExtension: "png")
        }
        // Fallback: some apps only vend an NSImage-readable representation.
        if let tiff = fallbackImageTIFF(),
           let png = pngData(fromTIFF: tiff) {
            return ClipboardPayload(kind: .image, data: png, fileExtension: "png")
        }
        return nil
    }

    private static func textPayload(
        types: [NSPasteboard.PasteboardType],
        data: (NSPasteboard.PasteboardType) -> Data?,
        string: (NSPasteboard.PasteboardType) -> String?
    ) -> ClipboardPayload? {
        if types.contains(.rtf), let rtf = data(.rtf) {
            return ClipboardPayload(kind: .text, data: rtf, fileExtension: "rtf")
        }
        if let text = string(.string), !text.isEmpty,
           let utf8 = text.data(using: .utf8) {
            return ClipboardPayload(kind: .text, data: utf8, fileExtension: "txt")
        }
        return nil
    }

    private static func pngData(fromTIFF tiff: Data) -> Data? {
        NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
