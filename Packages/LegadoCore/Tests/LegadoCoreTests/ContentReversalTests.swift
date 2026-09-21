import XCTest
@testable import LegadoCore

final class ContentReversalTests: XCTestCase {
    func testKotlinPlainTextReversesCodePointsAndMirrorsPairs() throws {
        XCTAssertEqual(try ContentReversal.reverse("ab\ncd"), "dc\nba")
        XCTAssertEqual(try ContentReversal.reverse("(a\u{1f600}b)"), "(b\u{1f600}a)")
        XCTAssertEqual(try ContentReversal.reverse("a\u{301}"), "\u{301}a")
        XCTAssertEqual(try ContentReversal.reverse(""), "")
    }

    func testKotlinRichContentPreservesMarkupParagraphsAndImageActions() throws {
        let image = #"<img src="https://image.test/x,{"action":"review"}">"#
        let input = "  abc " + image + "\r\n  def\n<usehtml><b>unchanged</b></usehtml>[newpage]&amp;ghi"
        XCTAssertEqual(try ContentReversal.reverse(input), "  cba " + image + "\r\n  fed\n<usehtml><b>unchanged</b></usehtml>[newpage]&amp;ihg")
    }

    func testCacheToggleRestoresOriginalEvenWhenReversalCreatesMarkup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var book = Book(); book.bookUrl = "https://reverse.test/book"; book.name = "Reverse"
        var chapter = BookChapter(); chapter.url = "1"; chapter.title = "One"
        let original = "<1a>abc"
        try BookHelp.save(original, directory: root, book: book, chapter: chapter)
        XCTAssertEqual(try BookHelp.reverseContent(directory: root, book: book, chapter: chapter), "cba<a1>")
        XCTAssertEqual(try BookHelp.reverseContent(directory: root, book: book, chapter: chapter), original)
        _ = try BookHelp.reverseContent(directory: root, book: book, chapter: chapter)
        try BookHelp.save("Edited", directory: root, book: book, chapter: chapter)
        XCTAssertEqual(try BookHelp.reverseContent(directory: root, book: book, chapter: chapter), "detidE")
        XCTAssertEqual(try BookHelp.reverseContent(directory: root, book: book, chapter: chapter), "Edited")
    }
}
