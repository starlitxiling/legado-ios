import XCTest
@testable import LegadoCore

final class EpubLazyReviewTests: XCTestCase {
    func testR6CacheIsBoundedAndInvalidatesReplacedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LocalBook/nav.epub")
        let data = try Data(contentsOf: fixture)
        let a = root.appendingPathComponent("a.epub"), b = root.appendingPathComponent("b.epub")
        try data.write(to: a); try data.write(to: b)
        let cache = EpubParserCache(capacity: 1, maximumBytes: data.count * 2)
        let first = try cache.parser(for: a)
        XCTAssertTrue(first === (try cache.parser(for: a)))
        let chapters = try first.chapters(bookURL: a.absoluteString)
        _ = try first.content(chapter: chapters[0])
        XCTAssertEqual(first.archive.readCount("OPS/b.xhtml"), 0)
        XCTAssertEqual(first.archive.readCount("OPS/c.xhtml"), 0)
        _ = try cache.parser(for: b)
        XCTAssertEqual(cache.count, 1)
        XCTAssertLessThanOrEqual(cache.cachedBytes, data.count * 2)
        XCTAssertFalse(first === (try cache.parser(for: a)))
        let current = try cache.parser(for: a)
        try data.write(to: a, options: .atomic)
        XCTAssertFalse(current === (try cache.parser(for: a)))
        let tiny = EpubParserCache(capacity: 1, maximumBytes: 1)
        _ = try tiny.parser(for: a)
        XCTAssertEqual(tiny.count, 0)
    }

    func testR6UnreferencedPayloadIsNotInflated() throws {
        var data = BackupReviewTests.archive([
            "META-INF/container.xml": "<container><rootfiles><rootfile full-path='book.opf'/></rootfiles></container>",
            "book.opf": "<package><metadata><title>按需读取</title></metadata><manifest><item id='a' href='a.xhtml'/></manifest><spine><itemref idref='a'/></spine></package>",
            "a.xhtml": "<html><head><title>章节</title></head><body>正文</body></html>",
            "unused.bin": "UNUSED_PAYLOAD"
        ])
        let range = try XCTUnwrap(data.range(of: Data("UNUSED_PAYLOAD".utf8)))
        data[range.lowerBound] ^= 1
        let parser = try EpubParser(data: data)
        XCTAssertEqual(parser.title, "按需读取")
        let chapters = try parser.chapters(bookURL: "file:///book.epub")
        XCTAssertTrue(try parser.content(chapter: XCTUnwrap(chapters.first)).contains("正文"))
    }
}
