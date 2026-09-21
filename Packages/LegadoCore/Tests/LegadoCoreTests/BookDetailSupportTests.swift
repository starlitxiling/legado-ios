import XCTest
@testable import LegadoCore

final class BookDetailSupportTests: XCTestCase {
    func testGeneratedUpdateTaskKeepsExistingTaskAcrossSourceChange() throws {
        var book = Book(now: 0); book.bookUrl = "https://a.test/book"; book.name = "Book"; book.author = "Author"
        var existing = try BookUpdateTask.build(book: book, name: "Update Book")
        XCTAssertEqual(existing.cron, "*/30 * * * *")
        let action = try JSONSerialization.jsonObject(with: Data(existing.script.dropFirst().dropLast().utf8)) as! [String: Any]
        XCTAssertEqual(action["generatedBy"] as? String, "bookUpdate")
        XCTAssertEqual(action["respectCanUpdate"] as? Bool, true)
        existing.enable = false
        book.bookUrl = "https://b.test/book"
        XCTAssertEqual(BookUpdateTask.find(book: book, tasks: [existing])?.id, existing.id)
        let duplicate = try BookUpdateTask.build(book: book, name: "Other")
        book.bookUrl = "https://c.test/book"
        XCTAssertNil(BookUpdateTask.find(book: book, tasks: [existing, duplicate]))
    }

    func testClearBookCacheRemovesRenamedFoldersAndLegacyContentOnlyForThatBook() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var book = Book(now: 0); book.bookUrl = "https://book.test/1"; book.name = "Old"
        var other = book; other.bookUrl = "https://book.test/2"
        var chapter = BookChapter(); chapter.index = 0; chapter.title = "Chapter"; chapter.url = "/1"
        try BookHelp.save("cached", directory: root, book: book, chapter: chapter)
        try BookHelp.save("retained", directory: root, book: other, chapter: chapter)
        let legacy = try ReaderCacheStatus.fileURL(book: book, chapter: chapter, directory: root)
        try Data("{\"rawContent\":\"legacy\"}".utf8).write(to: legacy)
        book.name = "Renamed"
        try BookHelp.clearCache(directory: root, book: book, chapters: [chapter])
        XCTAssertNil(try BookHelp.content(directory: root, book: book, chapter: chapter))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(try BookHelp.content(directory: root, book: other, chapter: chapter), "retained")
    }

    func testImageClickExposesResultBookChapterWithoutEventListener() throws {
        var source = BookSource(); source.bookSourceUrl = "https://click.test"; source.eventListener = false
        var book = Book(); book.name = "Book"; book.bookUrl = "https://click.test/book"
        var chapter = BookChapter(); chapter.title = "Chapter"; chapter.url = "https://click.test/1"
        XCTAssertEqual(try SourceCallback.imageClick(script: "book.name + \"|\" + chapter.title + \"|\" + result", src: "image", source: source, book: book, chapter: chapter, client: ReplayHttpClient()), "Book|Chapter|image")
    }

    func testSourceCallbackHonorsEventFlagAndExposesBookAndChapter() throws {
        var source = BookSource(); source.bookSourceUrl = "https://source.test"
        source.ruleContent = ContentRule(); source.ruleContent?.callBackJs = "event === 'clickCustomButton' && book.name === 'Book' && chapter.index === 2 && result === 'input'"
        var book = Book(now: 0); book.name = "Book"
        var chapter = BookChapter(); chapter.index = 2
        let client = ReplayHttpClient()
        XCTAssertFalse(try SourceCallback.run(source: source, book: book, chapter: chapter, event: "clickCustomButton", result: "input", client: client))
        source.eventListener = true
        XCTAssertTrue(try SourceCallback.run(source: source, book: book, chapter: chapter, event: "clickCustomButton", result: "input", client: client))
        XCTAssertFalse(try SourceCallback.run(source: source, book: book, event: "other", client: client))
    }
}
