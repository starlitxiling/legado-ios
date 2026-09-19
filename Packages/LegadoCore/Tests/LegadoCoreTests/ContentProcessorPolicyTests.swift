import XCTest
@testable import LegadoCore

final class ContentProcessorPolicyTests: XCTestCase {
    private func entities() -> (Book, BookChapter, ReplaceRule) {
        var book = Book(); book.bookUrl = "https://content.test/book"; book.name = "Book"; book.origin = "https://content.test"
        var chapter = BookChapter(); chapter.url = "chapter"; chapter.title = "Title"; chapter.bookUrl = book.bookUrl
        var rule = ReplaceRule(); rule.id = 1; rule.pattern = "body"; rule.replacement = "clean"
        rule.scopeTitle = true; rule.scopeContent = true
        return (book, chapter, rule)
    }

    func testReplacementDefaultsAndExplicitBookOverrides() throws {
        var (book, chapter, rule) = entities()
        let disabled = ContentProcessor(rules: [rule], replaceEnableDefault: false)
        XCTAssertEqual(try disabled.getContent(book: book, chapter: chapter, content: "body", includeTitle: false).text, "　　body")
        book.readConfig = ReadConfig(); book.readConfig?.useReplaceRule = true
        XCTAssertEqual(try disabled.getContent(book: book, chapter: chapter, content: "body", includeTitle: false).text, "　　clean")
        book.type = 64; book.readConfig = nil
        let enabled = ContentProcessor(rules: [rule])
        XCTAssertEqual(try enabled.getContent(book: book, chapter: chapter, content: "body", includeTitle: false).text, "　　body")
        book.type = 256; book.origin = "loc_book"; book.bookUrl = "file:///book.epub"
        XCTAssertEqual(try enabled.getContent(book: book, chapter: chapter, content: "body", includeTitle: false).text, "　　body")
        book.bookUrl = "file:///book.txt"
        XCTAssertEqual(try enabled.getContent(book: book, chapter: chapter, content: "body", includeTitle: false).text, "　　clean")
        book.readConfig = ReadConfig(); book.readConfig?.useReplaceRule = false
        XCTAssertEqual(try enabled.getContent(book: book, chapter: chapter, content: "body", includeTitle: false).text, "　　body")
        book.type = 0; book.origin = "https://content.test"; book.readConfig = nil
        rule.scopeContent = false; rule.scopeTitle = false; rule.scopeSource = true
        XCTAssertEqual(try ContentProcessor(rules: [rule]).getContent(book: book, chapter: chapter, content: "body", includeTitle: false).text, "　　body")
    }

    func testSpecialHTMLIsIsolatedAndRestoredAsSingleParagraph() throws {
        let (book, chapter, rule) = entities()
        let html = "<usehtml><b>body\nbody</b></usehtml>"
        let processor = ContentProcessor(rules: [rule])
        XCTAssertEqual(try processor.getContent(book: book, chapter: chapter, content: "body" + html + "body", includeTitle: false).paragraphs,
            ["　　clean", "　　<usehtml><b>bodybody</b></usehtml>", "　　clean"])
        let unprotected = ContentProcessor(rules: [rule], adaptSpecialStyle: false)
        XCTAssertTrue(try unprotected.getContent(book: book, chapter: chapter, content: html, includeTitle: false).text.contains("<b>clean"))
    }

    func testDuplicateTitleMarkerPersistsAndCanBeReenabled() throws {
        let (book, chapter, _) = entities()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let processor = ContentProcessor(cacheDirectory: directory)
        let raw = "Title\nbody"
        XCTAssertTrue(try processor.getContent(book: book, chapter: chapter, content: raw).sameTitleRemoved)
        try BookHelp.setRemoveSameTitle(false, directory: directory, book: book, chapter: chapter)
        XCTAssertFalse(try processor.getContent(book: book, chapter: chapter, content: raw).sameTitleRemoved)
        XCTAssertFalse(try ContentProcessor(cacheDirectory: directory).getContent(book: book, chapter: chapter, content: raw).sameTitleRemoved)
        try BookHelp.setRemoveSameTitle(true, directory: directory, book: book, chapter: chapter)
        XCTAssertTrue(try processor.getContent(book: book, chapter: chapter, content: raw).sameTitleRemoved)
    }

    func testBookResegmentFlagAndTitleWhitespace() throws {
        var (book, chapter, _) = entities()
        let processor = ContentProcessor()
        chapter.title = "Chapter  1"
        XCTAssertTrue(try processor.getContent(book: book, chapter: chapter, content: "Chapter 1\nbody").sameTitleRemoved)
        book.readConfig = ReadConfig(); book.readConfig?.reSegment = true
        XCTAssertEqual(try processor.getContent(book: book, chapter: chapter, content: "第一\n段结束。\n下一段。", includeTitle: false).paragraphs,
            ["　　第一段结束。", "　　下一段。"])
    }
}
