import XCTest
import LegadoCore
@testable import ReaderCheck

final class ReaderAlignmentTests: XCTestCase {
    func testScrollKeepsPartialScreenAndOverflow() {
        XCTAssertEqual(ReaderScrollStep.resolve(offset: 300, height: 800).pages, 0)
        XCTAssertEqual(ReaderScrollStep.resolve(offset: 300, height: 800).remainder, 300)
        XCTAssertEqual(ReaderScrollStep.resolve(offset: 800, height: 800).pages, 0)
        XCTAssertEqual(ReaderScrollStep.resolve(offset: 850, height: 800).pages, 1)
        XCTAssertEqual(ReaderScrollStep.resolve(offset: 850, height: 800).remainder, 50)
        XCTAssertEqual(ReaderScrollStep.resolve(offset: 1700, height: 800).remainder, 100)
    }

    func testAutoRevealIncludesProgressLineBeforeTurn() {
        let state = ReaderPresentationState(mode: 0, progress: 0.4, height: 800)
        XCTAssertEqual(state.revealHeight, 320)
        XCTAssertEqual(state.lineOffset, 319)
        XCTAssertEqual(ReaderPresentationState(mode: 3, progress: 0.4, height: 800).revealHeight, 0)
    }

    func testSlideHasDistinctMode() {
        XCTAssertEqual(ReaderPresentationState(mode: 1, progress: 0, height: 800).animation, .slide)
        XCTAssertEqual(ReaderPresentationState(mode: 0, progress: 0, height: 800).animation, .cover)
    }

    @MainActor
    func testLastPagePreviewsNextChapterAndReflows() async throws {
        let db = try AppDatabase.inMemory(), client = ReplayHttpClient()
        var book = BookRow(); book.bookUrl = "https://preview.test/book"; book.origin = "https://preview.test"
        try await BookshelfRepository(database: db).insert(book)
        var source = BookSourceRow(); source.bookSourceUrl = book.origin; source.ruleContent = #"{"content":"tag.p@text"}"#
        try await BookSourceRepository(database: db).insert(source)
        for index in 0...1 {
            var chapter = BookChapterRow(); chapter.bookUrl = book.bookUrl; chapter.index = index
            chapter.url = "https://preview.test/\(index)"; chapter.title = "第\(index)章"
            try await ChapterRepository(database: db).insert(chapter)
            let url = URL(string: chapter.url)!
            await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("<p>正文\(index)</p>".utf8), finalURL: url))
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/preview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ReaderViewModel(database: db, client: client, cacheDirectory: root, now: { 10 })
        await model.load(bookURL: book.bookUrl, chapterIndex: 0)
        await model.waitForPrefetch()
        XCTAssertTrue(model.nextPagePreview?.pagination.text.string.contains("正文1") == true)
        XCTAssertEqual(model.nextPagePreview?.index, 0)
        await model.reflow(size: CGSize(width: 280, height: 400))
        await model.waitForPrefetch()
        XCTAssertEqual(model.nextPagePreview?.pagination.contentSize.width, 248)
        await model.nextChapter()
        await model.waitForPrefetch()
        XCTAssertNil(model.nextPagePreview)
        await model.close()
    }
}
