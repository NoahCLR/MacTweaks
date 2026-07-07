import AppKit
import XCTest

final class ClipboardPayloadTests: XCTestCase {

    // MARK: - Helpers

    /// A real (small) TIFF, so the transcode path exercises actual bytes.
    private func sampleTIFF() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        return rep.tiffRepresentation!
    }

    private let jpegType = NSPasteboard.PasteboardType("public.jpeg")

    /// Builds a payload from explicit facts. Any type present in `data`/`string`
    /// is considered available unless `types` is given explicitly.
    private func payload(
        imageEnabled: Bool = true,
        textEnabled: Bool = true,
        types: [NSPasteboard.PasteboardType]? = nil,
        data: [NSPasteboard.PasteboardType: Data] = [:],
        strings: [NSPasteboard.PasteboardType: String] = [:],
        fallbackTIFF: Data? = nil
    ) -> ClipboardPayload? {
        let resolvedTypes = types ?? Array(Set(data.keys).union(strings.keys))
        return ClipboardPayload.from(
            types: resolvedTypes,
            imageEnabled: imageEnabled,
            textEnabled: textEnabled,
            data: { data[$0] },
            string: { strings[$0] },
            fallbackImageTIFF: { fallbackTIFF }
        )
    }

    // MARK: - Precedence

    func testImageWinsOverTextWhenBothPresent() {
        let result = payload(
            data: [.png: Data([0x89, 0x50])],
            strings: [.string: "hello"]
        )
        XCTAssertEqual(result?.kind, .image)
        XCTAssertEqual(result?.fileExtension, "png")
    }

    // MARK: - Image passthrough / transcode

    func testPNGPassesThroughUnchanged() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let result = payload(data: [.png: bytes])
        XCTAssertEqual(result?.kind, .image)
        XCTAssertEqual(result?.fileExtension, "png")
        XCTAssertEqual(result?.data, bytes)
    }

    func testJPEGPassesThroughUnchanged() {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let result = payload(data: [jpegType: bytes])
        XCTAssertEqual(result?.kind, .image)
        XCTAssertEqual(result?.fileExtension, "jpg")
        XCTAssertEqual(result?.data, bytes)
    }

    func testTIFFIsTranscodedToPNG() throws {
        let tiff = sampleTIFF()
        let result = payload(data: [.tiff: tiff])
        XCTAssertEqual(result?.kind, .image)
        XCTAssertEqual(result?.fileExtension, "png")
        XCTAssertNotEqual(result?.data, tiff, "TIFF should be transcoded, not passed through")
        let transcoded = try XCTUnwrap(result).data
        XCTAssertNotNil(NSBitmapImageRep(data: transcoded), "Output should be a decodable image")
    }

    func testPNGWinsOverTIFFWhenBothPresent() {
        let png = Data([0x89, 0x50])
        let result = payload(data: [.png: png, .tiff: sampleTIFF()])
        XCTAssertEqual(result?.fileExtension, "png")
        XCTAssertEqual(result?.data, png)
    }

    func testFallbackImageTIFFIsTranscodedWhenNoDirectImageType() throws {
        // No png/jpeg/tiff types available, but an NSImage-only representation is.
        let result = payload(
            types: [],
            fallbackTIFF: sampleTIFF()
        )
        XCTAssertEqual(result?.kind, .image)
        XCTAssertEqual(result?.fileExtension, "png")
        let transcoded = try XCTUnwrap(result).data
        XCTAssertNotNil(NSBitmapImageRep(data: transcoded))
    }

    // MARK: - Text

    func testRTFBecomesRTF() {
        let rtf = Data("{\\rtf1}".utf8)
        let result = payload(data: [.rtf: rtf], strings: [.string: "plain"])
        XCTAssertEqual(result?.kind, .text)
        XCTAssertEqual(result?.fileExtension, "rtf")
        XCTAssertEqual(result?.data, rtf)
    }

    func testPlainTextBecomesTxt() {
        let result = payload(strings: [.string: "hello world"])
        XCTAssertEqual(result?.kind, .text)
        XCTAssertEqual(result?.fileExtension, "txt")
        XCTAssertEqual(result?.data, Data("hello world".utf8))
    }

    func testEmptyStringYieldsNoTextPayload() {
        XCTAssertNil(payload(strings: [.string: ""]))
    }

    // MARK: - File references never hijacked

    func testFileReferenceReturnsNilEvenWithImage() {
        let result = payload(
            types: [.fileURL, .png],
            data: [.png: Data([0x89])]
        )
        XCTAssertNil(result, "Copied files must paste natively, never become a payload")
    }

    func testFilenamesPboardTypeReturnsNil() {
        let names = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let result = payload(types: [names, .png], data: [.png: Data([0x89])])
        XCTAssertNil(result)
    }

    // MARK: - Enable flags

    func testImageDisabledFallsBackToText() {
        let result = payload(
            imageEnabled: false,
            data: [.png: Data([0x89])],
            strings: [.string: "hello"]
        )
        XCTAssertEqual(result?.kind, .text)
        XCTAssertEqual(result?.fileExtension, "txt")
    }

    func testTextDisabledYieldsNilWhenOnlyText() {
        XCTAssertNil(payload(textEnabled: false, strings: [.string: "hello"]))
    }

    func testBothDisabledYieldsNil() {
        XCTAssertNil(payload(imageEnabled: false, textEnabled: false, data: [.png: Data([0x89])]))
    }

    // MARK: - Naming

    func testBaseNameAndKindDescriptionForImage() {
        let result = payload(data: [.png: Data([0x89])])
        XCTAssertEqual(result?.kindDescription, "image.png")
        XCTAssertEqual(result?.baseName.hasPrefix("Pasted Image "), true)
    }

    func testBaseNameForText() {
        let result = payload(strings: [.string: "hi"])
        XCTAssertEqual(result?.kindDescription, "text.txt")
        XCTAssertEqual(result?.baseName.hasPrefix("Pasted Text "), true)
    }
}
