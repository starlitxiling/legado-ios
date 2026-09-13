import XCTest
@testable import LegadoCore

final class EpubParserTests: XCTestCase {
    private func fixture(_ kind: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LocalBook/\(kind).epub")
    }

    func testNavAndNCXBoundaries() throws {
        for kind in ["nav", "ncx"] {
            let parser = try EpubParser(url: fixture(kind))
            XCTAssertEqual(parser.title, "合成书")
            XCTAssertEqual(parser.author, "合成作者")
            XCTAssertEqual(parser.cover, Data("synthetic-image".utf8))
            let chapters = try parser.chapters(bookURL: "file:///book.epub")
            XCTAssertEqual(chapters.map(\.title), ["一", "二", "三"])
            let first = try parser.content(chapter: chapters[0])
            XCTAssertTrue(first.contains("第一段。"))
            XCTAssertTrue(first.contains("[图片：插图]"))
            XCTAssertFalse(first.contains("第二段。"))
            let second = try parser.content(chapter: chapters[1])
            XCTAssertTrue(second.contains("第二段。"))
            XCTAssertTrue(second.contains("接续正文。"))
            XCTAssertFalse(second.contains("最后一段。"))
            XCTAssertTrue(try parser.content(chapter: chapters[2]).contains("最后一段。"))
        }
    }

    func testRepairsMissingCentralDirectoryAndRejectsCorruptPayload() throws {
        let data = try Data(contentsOf: fixture("nav"))
        let central = try XCTUnwrap(data.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        let truncated = Data(data[..<central.lowerBound])
        let parser = try EpubParser(data: truncated)
        XCTAssertEqual(parser.title, "合成书")
        var corrupt = truncated
        corrupt[30 + "mimetype".utf8.count] ^= 1
        XCTAssertThrowsError(try ZipReader(data: corrupt).readEntry("mimetype"))
    }

    func testSpineFallbackAndBadZip() throws {
        let parser = try EpubParser(url: fixture("spine"))
        let chapters = try parser.chapters(bookURL: "file:///book.epub")
        XCTAssertEqual(chapters.map(\.title), ["第一文件", "补充", "最后文件"])
        XCTAssertThrowsError(try EpubParser(data: Data("not zip".utf8)))
    }

    func testLocalRoutingAvoidsNetwork() async throws {
        var parsed = try LocalBook.parse(url: fixture("nav"))
        let web = WebBook(source: BookSource(), client: ReplayHttpClient())
        let chapters = try await web.chapterList(book: &parsed.book)
        XCTAssertEqual(chapters.count, 3)
        let result = try await web.content(book: parsed.book, chapter: chapters[0], includeTitle: false)
        XCTAssertTrue(result.rawContent.contains("第一段。"))
        var remote = parsed.book
        remote.origin = "https://example.invalid"
        XCTAssertFalse(LocalBook.isLocal(remote))
    }
}
