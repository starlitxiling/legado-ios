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
}
