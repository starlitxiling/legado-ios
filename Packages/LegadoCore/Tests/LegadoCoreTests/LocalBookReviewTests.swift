import XCTest
@testable import LegadoCore

final class LocalBookReviewTests: XCTestCase {
    private func file(_ data: Data, _ body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }

    func testR1RefreshPreservesProgressAndConflictPreservesNetworkBook() async throws {
        let db = try AppDatabase.inMemory()
        var book = Book(); book.bookUrl = "file:///old.txt"; book.name = "同名书"; book.author = "作者"
        book.durChapterPos = 123; book.durChapterIndex = 4
        var chapter = BookChapter(); chapter.bookUrl = book.bookUrl; chapter.url = "old"; chapter.title = "旧章"
        try await LocalBook.save(book: book, chapters: [chapter], database: db)
        var refreshed = book; refreshed.durChapterPos = 0; refreshed.durChapterIndex = 0
        chapter.url = "new"; chapter.title = "新章"
        try await LocalBook.save(book: refreshed, chapters: [chapter], database: db)
        let stored = try await BookshelfRepository(database: db).get(bookUrl: book.bookUrl!)
        XCTAssertEqual(stored?.durChapterPos, 123)
        XCTAssertEqual(stored?.durChapterIndex, 4)
        let chapters = try await ChapterRepository(database: db).list(bookUrl: book.bookUrl!)
        XCTAssertEqual(chapters.map(\.url), ["new"])
        var remote = BookRow(); remote.bookUrl = "https://example.invalid/book"; remote.name = "网络书"; remote.author = "作者"
        try await BookshelfRepository(database: db).insert(remote)
        refreshed.bookUrl = "file:///new.txt"; refreshed.name = "网络书"
        do { try await LocalBook.save(book: refreshed, chapters: [], database: db); XCTFail("必须报告身份冲突") }
        catch {}
        let retained = try await BookshelfRepository(database: db).get(bookUrl: remote.bookUrl)
        XCTAssertNotNil(retained)
    }

    func testR2ExactMatchByteOffsets() throws {
        try file(Data("前文===标题===后文".utf8)) { url in
            let parser = try TextFileParser(url: url, blockSize: 7)
            let rules = [TxtTocRule(id: 1, name: "同行", rule: "===标题===")]
            let chapters = try parser.chapters(bookURL: url.absoluteString, rules: rules)
            XCTAssertEqual(chapters.count, 2)
            guard chapters.count == 2 else { return }
            XCTAssertEqual(chapters[0].end, 6)
            XCTAssertEqual(chapters[1].start, 18)
            XCTAssertEqual(try parser.content(chapter: chapters[0]), "前文")
            XCTAssertEqual(try parser.content(chapter: chapters[1]), "后文")
        }
    }

    func testR3MultilineMatchCrossesReadBlocks() throws {
        let text = "前文\n第一章\n副标题\n正文\n第二章\n另一副标题\n结尾"
        try file(Data(text.utf8)) { url in
            let parser = try TextFileParser(url: url, blockSize: 7)
            let rules = [TxtTocRule(id: 1, name: "双行", rule: #"第[一二]章\n[^\n]+"#)]
            let chapters = try parser.chapters(bookURL: url.absoluteString, rules: rules)
            XCTAssertEqual(chapters.map(\.title), ["前言", "第一章\n副标题", "第二章\n另一副标题"])
            guard chapters.count == 3 else { return }
            XCTAssertEqual(try parser.content(chapter: chapters[1]), "\n正文\n")
            XCTAssertEqual(try parser.content(chapter: chapters[2]), "\n结尾")
        }
    }

    func testR4FixedEncodingSamples() throws {
        let samples: [(Data, String, String)] = [
            (Data([0xff,0xfe,0,0,0x2d,0x4e,0,0]), "UTF-32LE", "中"),
            (Data([0,0,0xfe,0xff,0,0,0x4e,0x2d]), "UTF-32BE", "中"),
            (Data([0x41,0,0x42,0,0x43,0,0x44,0]), "UTF-16LE", "ABCD"),
            (Data([0,0x41,0,0x42,0,0x43,0,0x44]), "UTF-16BE", "ABCD"),
            (Data([0xe4,0xb8,0xad,0xe6,0x96,0x87]), "UTF-8", "中文"),
            (Data([0xd6,0xd0,0xce,0xc4]), "GBK", "中文"),
            (Data([0xa4,0xa4,0xa4,0xe5,0xb4,0xfa,0xb8,0xd5]), "Big5", "中文測試"),
            (Data([0x90,0x30,0x81,0x30]), "GB18030", "𐀀")
        ]
        for (data, charset, text) in samples {
            try file(data) { url in
                let parser = try TextFileParser(url: url)
                XCTAssertEqual(parser.charset, charset)
                let chapters = try parser.chapters(bookURL: url.absoluteString, rules: [])
                XCTAssertEqual(try parser.content(chapter: XCTUnwrap(chapters.first)), text)
            }
        }
    }

    func testR5FilenameFallbackAuthor() {
        XCTAssertEqual(LocalBook.nameAuthor("书名 作者:张三.txt").name, "书名")
        XCTAssertEqual(LocalBook.nameAuthor("书名 作者:张三.txt").author, "张三")
        XCTAssertEqual(LocalBook.nameAuthor("书名 张三 著.txt").author, "张三")
        XCTAssertEqual(LocalBook.nameAuthor("张三 著.txt").name, "张三 著")
        XCTAssertEqual(LocalBook.nameAuthor("张三 著.txt").author, "")
    }
}
