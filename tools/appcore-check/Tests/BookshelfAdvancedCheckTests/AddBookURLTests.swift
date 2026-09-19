import XCTest
import LegadoCore
@testable import BookshelfAdvancedCheck

@MainActor
final class AddBookURLTests: XCTestCase {
    func testExistingURLMergesGroupsWithoutNetworkAndReportsMissingSource() async throws {
        let database = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: database)
        var book = BookRow(); book.bookUrl = "https://book.test/existing"; book.name = "Existing"; book.group = 2
        try await shelf.insert(book)
        let client = ReplayHttpClient()
        let model = AddBookURLModel(database: database, client: client)
        model.input = "\nhttps://book.test/existing\nhttps://unknown.test/book"
        await model.add(groupID: 4)
        XCTAssertEqual(model.completed, 1)
        XCTAssertEqual(model.failures.count, 1)
        let saved = try await shelf.get(bookUrl: book.bookUrl)
        XCTAssertEqual(saved?.group, 6)
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
        model.input = book.bookUrl
        await model.add(groupID: -1)
        let unchanged = try await shelf.get(bookUrl: book.bookUrl)
        XCTAssertEqual(unchanged?.group, 6)
    }

    func testExplicitOriginFetchesBookAndMigratesReadingState() async throws {
        let database = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: database)
        var source = BookSource(); source.bookSourceUrl = "https://specified.test"; source.bookSourceName = "Specified"
        source.bookUrlPattern = #"https://book\.test/.*"#
        source.ruleBookInfo = BookInfoRule(); source.ruleBookInfo?.name = "tag.h1@text"
        source.ruleBookInfo?.author = "tag.b@text"; source.ruleBookInfo?.tocUrl = "tag.nav@data-url"
        source.ruleToc = TocRule(); source.ruleToc?.chapterList = "tag.a"
        source.ruleToc?.chapterName = "text"; source.ruleToc?.chapterUrl = "href"
        try await BookSourceRepository(database: database).insert(DiscoveryStorage.row(source, defaults: BookSourceRow()))
        var old = BookRow(); old.bookUrl = "https://old.test/book"; old.name = "Book"; old.author = "Writer"
        old.group = 2; old.durChapterTitle = "Chapter"; old.durChapterPos = 9; old.customCoverUrl = "custom-cover"
        try await shelf.insert(old)
        let client = ReplayHttpClient()
        for (path, body) in [("/book", "<h1>Book</h1><b>Writer</b><nav data-url='/toc'></nav>"),
                             ("/toc", "<a href='/chapter'>Chapter</a>")] {
            let url = URL(string: "https://book.test" + path)!
            await client.enqueue(url: url, response: .init(status: 200, body: Data(body.utf8), finalURL: url))
        }
        let model = AddBookURLModel(database: database, client: client)
        model.input = #"https://book.test/book,{"origin":"https://specified.test"}"#
        await model.add(groupID: 4)
        XCTAssertEqual(model.failures, [])
        XCTAssertEqual(model.completed, 1)
        let books = try await shelf.all()
        let saved = try XCTUnwrap(books.first)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(saved.origin, "https://specified.test")
        XCTAssertEqual(saved.group, 6)
        XCTAssertEqual(saved.durChapterPos, 9)
        XCTAssertEqual(saved.customCoverUrl, "custom-cover")
        let chapters = try await ChapterRepository(database: database).list(bookUrl: saved.bookUrl)
        XCTAssertEqual(chapters.map(\.title), ["Chapter"])
    }
}
