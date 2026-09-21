import XCTest
@testable import LegadoCore

final class TextEncodingParityTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/localbook")
    }

    func testMultilingualFilesDecodeWithoutLossThroughLastChapter() throws {
        for name in ["shift-jis", "euc-jp", "euc-kr", "windows-1251", "windows-1252", "latin1", "gbk", "utf16"] {
            let parser = try TextFileParser(url: fixtures.appendingPathComponent(name + ".txt"), blockSize: 7)
            let chapters = try parser.chapters(bookURL: "fixture:" + name, rules: [])
            let text = try chapters.map { try parser.content(chapter: $0) }.joined()
            XCTAssertEqual(text, try String(contentsOf: fixtures.appendingPathComponent(name + ".expected"), encoding: .utf8), name + ": " + parser.charset)
        }
    }

    func testSamplingReachesNonASCIIAfter64KiBAndMetaCharsetWithoutHead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let body = try Data(contentsOf: fixtures.appendingPathComponent("shift-jis.txt"))
        try (Data(repeating: 0x20, count: 70_000) + body).write(to: url)
        XCTAssertEqual(try TextFileParser(url: url).charset, "Shift_JIS")
        let html = "<meta charset='windows-1252'><p>caf\u{e9}</p>"
        let data = try XCTUnwrap(html.data(using: .windowsCP1252))
        XCTAssertEqual(TextEncodingDetector.detect(data, truncated: false).name.lowercased(), "windows-1252")
        XCTAssertEqual(try ResponseDecoder.decode(data), html)
        XCTAssertEqual(try ResponseDecoder.decode(Data("<head lang='en'><meta http-equiv='Content-Type' content='text/html; charset=ISO-8859-1'></head>".utf8)), "<head lang='en'><meta http-equiv='Content-Type' content='text/html; charset=ISO-8859-1'></head>")
    }
}
