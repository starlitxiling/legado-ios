import XCTest
import LegadoCore
@testable import ReaderCheck

@MainActor
final class ReadAloudReaderTests: XCTestCase {
    func testParagraphProgressTurnsPageAndPersistsUTF16Offset() async throws {
        let database = try AppDatabase.inMemory(), client = ReplayHttpClient()
        var book = BookRow(); book.bookUrl = "https://tts-reader.test/book"; book.origin = "https://tts-reader.test"; book.name = "听书"
        try await BookshelfRepository(database: database).insert(book)
        var source = BookSourceRow(); source.bookSourceUrl = book.origin; source.ruleContent = #"{"content":"tag.p@text"}"#
        try await BookSourceRepository(database: database).insert(source)
        var chapter = BookChapterRow(); chapter.bookUrl = book.bookUrl; chapter.url = "https://tts-reader.test/chapter"; chapter.title = "测试"
        try await ChapterRepository(database: database).insert(chapter)
        let url = URL(string: chapter.url)!
        await client.enqueue(url: url, response: .init(status: 200, body: Data(("<p>" + String(repeating: "中文😀长段测试文字。", count: 100) + "</p>").utf8), finalURL: url))
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/tts-reader-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ReaderViewModel(database: database, client: client, cacheDirectory: directory, now: { 123 })
        await model.load(bookURL: book.bookUrl)
        let pagination = try XCTUnwrap(model.pagination)
        let range = try XCTUnwrap(ReadAloudParagraph.split(pagination.text.string).last?.range)
        let speechOffset = pagination.pages.last!.range.location
        model.followReadAloud(chapter: model.chapterIndex, range: range, offset: speechOffset)
        XCTAssertEqual(model.pageIndex, pagination.pageIndex(at: speechOffset))
        XCTAssertGreaterThan(model.pageIndex, 0)
        XCTAssertEqual(model.readAloudRange, range)
        await model.saveProgress()
        let saved = try await BookshelfRepository(database: database).get(bookUrl: book.bookUrl)
        XCTAssertEqual(saved?.durChapterPos, speechOffset)
        model.followReadAloud(chapter: model.chapterIndex + 1, range: NSRange(location: 0, length: 1))
        XCTAssertEqual(model.readAloudRange, range)
        model.clearReadAloudHighlight(); XCTAssertNil(model.readAloudRange)
        await model.close()
    }
    func testUnloadedReaderIgnoresProgress() throws {
        let model = ReaderViewModel(database: try AppDatabase.inMemory(), client: ReplayHttpClient(),
            cacheDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/tts-reader"))
        model.followReadAloud(chapter: 0, range: NSRange(location: 10, length: 2))
        XCTAssertNil(model.readAloudRange)
        XCTAssertEqual(model.characterOffset, 0)
    }
}
