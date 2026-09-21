import XCTest
import LegadoCore
@testable import ReaderCheck

@MainActor
final class ReaderChapterUpdateTests: XCTestCase {
    func testNearEndRefreshAddsChaptersAndThrottlesRepeatedLoads() async throws {
        let db = try AppDatabase.inMemory(), client = ReplayHttpClient()
        var book = BookRow(); book.bookUrl = "https://update.test/book"; book.name = "Book"
        book.origin = "https://update.test"; book.tocUrl = "https://update.test/toc"; book.totalChapterNum = 1
        try await BookshelfRepository(database: db).insert(book)
        var source = BookSourceRow(); source.bookSourceUrl = book.origin
        source.ruleToc = #"{"chapterList":"tag.a","chapterName":"text","chapterUrl":"href"}"#
        source.ruleContent = #"{"content":"tag.p@text"}"#
        try await BookSourceRepository(database: db).insert(source)
        var chapter = BookChapterRow(); chapter.bookUrl = book.bookUrl; chapter.url = "https://update.test/0"; chapter.title = "First"
        try await ChapterRepository(database: db).insert(chapter)
        for index in 0...1 {
            let url = URL(string: "https://update.test/\(index)")!
            await client.enqueue(url: url, response: .init(status: 200, body: Data("<p>Body \(index)</p>".utf8), finalURL: url))
        }
        let toc = URL(string: book.tocUrl)!
        await client.enqueue(url: toc, response: .init(status: 200, body: Data("<a href='/0'>First</a><a href='/1'>Second</a>".utf8), finalURL: toc))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ReaderViewModel(database: db, client: client, cacheDirectory: directory, now: { 1_000_000 })
        await model.load(bookURL: book.bookUrl)
        await model.waitForChapterUpdates()
        await model.waitForPrefetch()
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.prefetchErrorMessage)
        XCTAssertEqual(model.chapters.map(\.title), ["First", "Second"])
        XCTAssertEqual(model.chapterIndex, 0)
        XCTAssertEqual(model.book?.lastCheckTime, 1_000_000)
        await model.load(bookURL: book.bookUrl)
        await model.waitForChapterUpdates()
        await model.waitForPrefetch()
        let requests = await client.requests
        XCTAssertEqual(requests.filter { $0.url == toc }.count, 1)
        await client.enqueue(url: toc, response: .init(status: 200, body: Data("<a href='/0'>Renamed</a><a href='/1'>Second</a>".utf8), finalURL: toc))
        await model.refreshFromScript("refreshBookToc")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.chapters.first?.title, "Renamed")
        XCTAssertEqual(model.chapterIndex, 0)
        await model.close()
    }
}
