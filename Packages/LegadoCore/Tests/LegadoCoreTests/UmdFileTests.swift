import XCTest
@testable import LegadoCore

final class UmdFileTests: XCTestCase {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/localbook/synthetic.umd")
    }

    func testMetadataTitlesChunksAndLastChapterThroughLocalBook() throws {
        let parsed = try LocalBook.parse(url: fixture)
        XCTAssertEqual(parsed.book.name, "Synthetic UMD")
        XCTAssertEqual(parsed.book.author, "Fixture Author")
        XCTAssertEqual(parsed.book.kind, "Fiction")
        XCTAssertEqual(parsed.cover, Data("fixture-cover".utf8))
        XCTAssertEqual(parsed.chapters.map(\.title), ["Opening", "Ending"])
        XCTAssertEqual(parsed.chapters.map(\.url), ["0", "1"])
        XCTAssertEqual(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[0]), "First paragraph\nSecond paragraph")
        XCTAssertEqual(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[1]), "The final page.")
        XCTAssertEqual(try LocalBook.chapterList(book: parsed.book).map(\.title), parsed.chapters.map(\.title))
    }

    func testRejectsCorruptCompressedContentAndLimits() throws {
        let data = try Data(contentsOf: fixture)
        XCTAssertThrowsError(try UmdFile(data: data, maximumExpandedSize: 20))
        var corrupt = data
        let header = try XCTUnwrap(corrupt.range(of: Data([0x78, 0x9c])))
        corrupt[header.upperBound + 3] ^= 0xff
        XCTAssertThrowsError(try UmdFile(data: corrupt))
        var invalidOffset = data
        let offsets = try XCTUnwrap(invalidOffset.range(of: Data([0x24, 17, 0, 0, 0, 17, 0, 0, 0])))
        invalidOffset[offsets.upperBound] = 1
        XCTAssertThrowsError(try UmdFile(data: invalidOffset))
    }

    func testEveryTruncationAndInvalidChapterFailsWithoutTrap() throws {
        let data = try Data(contentsOf: fixture)
        for count in 0..<data.count {
            XCTAssertThrowsError(try UmdFile(data: Data(data.prefix(count))), "Truncation at \(count)")
        }
        let parser = try UmdFile(data: data)
        var chapter = BookChapter(); chapter.url = "-1"
        XCTAssertThrowsError(try parser.content(chapter: chapter))
    }

    func testParserCacheReusesAndInvalidatesChangedFilesWithinBudget() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".umd")
        try Data(contentsOf: fixture).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = UmdParserCache(capacity: 1, maximumBytes: 1024)
        let first = try cache.parser(for: url)
        XCTAssertTrue(first === (try cache.parser(for: url)))
        XCTAssertEqual(cache.count, 1)
        XCTAssertLessThanOrEqual(cache.cachedBytes, 1024)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: url.path)
        XCTAssertFalse(first === (try cache.parser(for: url)))
        cache.invalidate(url)
        XCTAssertEqual(cache.count, 0)
        let small = UmdParserCache(maximumBytes: 1)
        _ = try small.parser(for: url)
        XCTAssertEqual(small.count, 0)
    }
}
