import XCTest
import LegadoCore
@testable import AppCoreCheck

@MainActor
final class BookDetailActionsTests: XCTestCase {
    func testReadingPreparationDoesNotAddToShelfAndSettingsPersist() async throws {
        let database = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: database)
        var book = Book(now: 0)
        book.bookUrl = "https://book.test/1"; book.name = "Book"; book.author = "Author"
        let model = BookDetailViewModel(results: [], sources: BookSourceRepository(database: database),
            bookshelf: shelf, client: ReplayHttpClient(), initialBook: book)
        let prepared = await model.prepareForReading(database: database)
        XCTAssertEqual(prepared?.bookUrl, book.bookUrl)
        let visible = try await shelf.list()
        XCTAssertTrue(visible.isEmpty)
        await model.setCanUpdate(false)
        await model.setVariable("{\"mode\":\"fast\"}")
        await model.setSplitLongChapter(false)
        let fetched = try await shelf.get(bookUrl: book.bookUrl!)
        let saved = try XCTUnwrap(fetched)
        XCTAssertFalse(saved.canUpdate)
        XCTAssertEqual(saved.variable, "{\"mode\":\"fast\"}")
        XCTAssertEqual(try JSONDecoder().decode(ReadConfig.self, from: Data(saved.readConfig!.utf8)).splitLongChapter, false)
        await model.toggleBookshelf()
        XCTAssertTrue(model.isOnBookshelf)
        let refetched = try await shelf.get(bookUrl: book.bookUrl!)
        var edited = try XCTUnwrap(refetched)
        edited.customIntro = "Changed"; edited.durChapterIndex = 3
        try await shelf.upsert(edited)
        await model.refreshShelfState()
        XCTAssertEqual(model.book?.customIntro, "Changed")
        XCTAssertEqual(model.book?.durChapterIndex, 3)
    }

    func testRefreshPersistsNewDetailsAndKeepsReadingProgress() async throws {
        let database = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: database)
        let sources = BookSourceRepository(database: database)
        var source = BookSourceRow(); source.bookSourceUrl = "https://source.test"
        source.mainJs = "function getBookInfo(book) { return {intro:'Updated introduction',tocUrl:'https://source.test/toc'}; }"
        try await sources.upsert(source)
        var book = BookRow(); book.bookUrl = "https://source.test/book"; book.origin = source.bookSourceUrl
        book.name = "Book"; book.author = "Author"; book.intro = "Old"; book.durChapterIndex = 4; book.durChapterPos = 20
        try await shelf.upsert(book)
        var result = SearchBook(); result.bookUrl = book.bookUrl; result.origin = book.origin; result.name = book.name
        let model = BookDetailViewModel(results: [result], sources: sources, bookshelf: shelf, client: ReplayHttpClient())
        await model.load()
        XCTAssertNil(model.errorMessage)
        let saved = try await shelf.get(bookUrl: book.bookUrl)
        XCTAssertEqual(saved?.intro, "Updated introduction")
        XCTAssertEqual(saved?.durChapterIndex, 4)
        XCTAssertEqual(saved?.durChapterPos, 20)
    }

    func testInvalidVariableIsReportedWithoutChangingSavedValue() async throws {
        let database = try AppDatabase.inMemory()
        var book = Book(now: 0); book.bookUrl = "https://book.test/2"; book.name = "Book"
        book.variable = "{\"key\":\"value\"}"
        let model = BookDetailViewModel(results: [], sources: BookSourceRepository(database: database),
            bookshelf: BookshelfRepository(database: database), client: ReplayHttpClient(), initialBook: book)
        await model.setVariable("[]")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.book?.variable, book.variable)
    }

    func testCoverCandidatesKeepDefaultRuleAndMatchingSourcesOnly() {
        func result(_ origin: String, name: String = "Book", author: String = "作者：Author", cover: String?) -> SearchBook {
            var book = SearchBook(); book.origin = origin; book.originName = origin; book.name = name; book.author = author
            book.coverUrl = cover; book.bookUrl = origin + "/b"; return book
        }
        let items = CoverCandidate.merge(name: "Book", author: "Author", rule: "https://rule.test/c.jpg", results: [
            result("a", cover: "https://a.test/c.jpg"), result("b", cover: "https://a.test/c.jpg"),
            result("c", name: "Other", cover: "https://c.test/c.jpg"), result("d", author: "Else", cover: "https://d.test/c.jpg"),
            result("e", cover: nil), result("f", cover: "https://rule.test/c.jpg")
        ])
        XCTAssertEqual(items.map(\.coverUrl), [CoverCandidate.defaultCoverURL, "https://rule.test/c.jpg", "https://a.test/c.jpg"])
        XCTAssertEqual(items.map(\.originName), ["默认封面", "封面规则", "a"])
    }

    func testCustomCoverPersistsForSavedBookAndStaysInMemoryOtherwise() async throws {
        let database = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: database)
        var book = Book(now: 0); book.bookUrl = "https://book.test/cover"; book.name = "Book"
        let transient = BookDetailViewModel(results: [], sources: BookSourceRepository(database: database),
            bookshelf: shelf, client: ReplayHttpClient(), initialBook: book)
        await transient.setCustomCover("https://cover.test/1.jpg")
        XCTAssertEqual(transient.book?.customCoverUrl, "https://cover.test/1.jpg")
        let missing = try await shelf.get(bookUrl: book.bookUrl!)
        XCTAssertNil(missing)
        _ = await transient.prepareForReading(database: database)
        await transient.setCustomCover(CoverCandidate.defaultCoverURL)
        let saved = try await shelf.get(bookUrl: book.bookUrl!)
        XCTAssertEqual(saved?.customCoverUrl, CoverCandidate.defaultCoverURL)
    }
}
