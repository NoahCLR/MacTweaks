import XCTest

final class FinderInputContextTests: XCTestCase {

    // MARK: - url(fromFinderLocation:)

    func testFileURLStringIsCoercedToStandardizedFileURL() {
        let url = FinderInputContext.url(fromFinderLocation: "file:///Users/example/Documents/")
        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(url.path, "/Users/example/Documents")
    }

    func testPOSIXPathIsCoercedToFileURL() {
        let url = FinderInputContext.url(fromFinderLocation: "/Users/example/Downloads")
        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(url.path, "/Users/example/Downloads")
    }

    func testFileURLWithPercentEncodingIsDecoded() {
        let url = FinderInputContext.url(fromFinderLocation: "file:///Users/example/My%20Folder/")
        XCTAssertEqual(url.path, "/Users/example/My Folder")
    }

    func testPathWithSpacesIsPreserved() {
        let url = FinderInputContext.url(fromFinderLocation: "/Users/example/My Folder")
        XCTAssertEqual(url.path, "/Users/example/My Folder")
    }

    func testTrailingSlashIsStandardizedAway() {
        let withSlash = FinderInputContext.url(fromFinderLocation: "/Applications/")
        let withoutSlash = FinderInputContext.url(fromFinderLocation: "/Applications")
        XCTAssertEqual(withSlash, withoutSlash)
    }

    func testNonFileURLSchemeFallsBackToTreatingWholeStringAsPath() {
        // Not a file URL, so it is treated as a POSIX path verbatim.
        let url = FinderInputContext.url(fromFinderLocation: "/tmp/plain-path")
        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(url.path, "/tmp/plain-path")
    }

    // MARK: - shouldUseURLAsFinderItem

    func testExistingFileIsUsableAsFinderItem() {
        // A path guaranteed to exist on every macOS install.
        let url = URL(fileURLWithPath: "/System/Library")
        XCTAssertTrue(FinderInputContext.shouldUseURLAsFinderItem(url))
    }

    func testNonExistentPathIsNotUsable() {
        let url = URL(fileURLWithPath: "/no/such/path/\(UUID().uuidString)")
        XCTAssertFalse(FinderInputContext.shouldUseURLAsFinderItem(url))
    }

    func testFilesystemRootIsNotUsable() {
        XCTAssertFalse(FinderInputContext.shouldUseURLAsFinderItem(URL(fileURLWithPath: "/")))
    }

    func testVolumesRootIsNotUsable() {
        XCTAssertFalse(FinderInputContext.shouldUseURLAsFinderItem(URL(fileURLWithPath: "/Volumes")))
    }

    // MARK: - appleScriptStringLiteral

    func testAppleScriptStringLiteralWrapsPlainPathInQuotes() {
        XCTAssertEqual(FinderInputContext.appleScriptStringLiteral("/Users/me/Desktop"), "\"/Users/me/Desktop\"")
    }

    func testAppleScriptStringLiteralEscapesQuotesAndBackslashes() {
        // Input:  /a"b\c   → escaped: /a\"b\\c   → wrapped: "/a\"b\\c"
        XCTAssertEqual(FinderInputContext.appleScriptStringLiteral("/a\"b\\c"), "\"/a\\\"b\\\\c\"")
    }
}
