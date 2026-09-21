import XCTest
import LegadoCore
@testable import AppCoreCheck

@MainActor
final class SearchInterfaceTests: XCTestCase {
    func testScopeGroupsDisabledExplicitSourceAndFallback() async throws {
        let db = try AppDatabase.inMemory()
        let repository = BookSourceRepository(database: db)
        for (url, name, group, enabled, order) in [("a", "A", "Fantasy;History", true, 1), ("b", "B:Source", "Fantasy", false, 0), ("c", "C", "History，Other", true, 2)] {
            var row = BookSourceRow(); row.bookSourceUrl = url; row.bookSourceName = name
            row.bookSourceGroup = group; row.enabled = enabled; row.customOrder = order
            row.jsLib = String(repeating: "script", count: 1000)
            try await repository.insert(row)
        }
        let sources = try await repository.summaries()
        XCTAssertEqual(sources.map(\.id), ["b", "a", "c"])
        let grouped = SearchScope(value: "Fantasy,Missing").resolve(sources)
        XCTAssertEqual(grouped.scope.value, "Fantasy")
        XCTAssertEqual(grouped.sources.map(\.id), ["a"])
        let combined = SearchScope(value: "Fantasy,History").resolve(sources)
        XCTAssertEqual(combined.sources.map(\.id), ["a", "c"])
        XCTAssertEqual(SearchScope.source(sources[0]).value, "BSource::b")
        XCTAssertEqual(SearchScope(value: "BSource::b").resolve(sources).sources.map(\.id), ["b"])
        let fallback = SearchScope(value: "Missing").resolve(sources)
        XCTAssertEqual(fallback.scope.value, "")
        XCTAssertEqual(fallback.sources.map(\.id), ["a", "c"])
        XCTAssertEqual(SearchScope(value: "Old::gone").resolve(sources).sources.map(\.id), ["a", "c"])
    }

    func testInputHelpHistoryDeletionAndReadingIndicators() async throws {
        let db = try AppDatabase.inMemory()
        var shelf = BookRow(); shelf.bookUrl = "saved"; shelf.name = "Ocean"; shelf.author = "Writer"
        var hidden = BookRow(); hidden.bookUrl = "hidden"; hidden.name = "Hidden"; hidden.type = 1024
        try await BookshelfRepository(database: db).upsert([shelf, hidden])
        var record = ReadRecordRow(); record.bookName = "Read"; record.author = "\u{001e}authors:[\"A\",\"B\"]"
        var legacy = ReadRecordRow(); legacy.bookName = "Legacy"; legacy.author = ""
        try await ReadProgressRepository(database: db).upsert([record, legacy])
        let keywords = SearchKeywordRepository(database: db)
        try await keywords.record("Ocean", at: 2); try await keywords.record("Other", at: 1)
        let model = SearchViewModel(sources: BookSourceRepository(database: db), client: ReplayHttpClient(), keywords: keywords,
            bookshelf: BookshelfRepository(database: db), records: ReadProgressRepository(database: db))
        await model.loadInputHelp()
        XCTAssertEqual(model.matchingShelf.map(\.name), ["Ocean"])
        model.query = "oce"
        XCTAssertEqual(model.matchingHistory.map(\.word), ["Ocean"])
        await model.deleteHistory(try XCTUnwrap(model.history.first))
        XCTAssertTrue(model.matchingHistory.isEmpty)
        var book = SearchBook(); book.name = "Ocean"; book.author = ""
        XCTAssertTrue(model.isOnShelf(book))
        book.author = "Different"; XCTAssertFalse(model.isOnShelf(book))
        book.bookUrl = "saved"; XCTAssertTrue(model.isOnShelf(book))
        book.name = "Read"; book.author = "B"; XCTAssertTrue(model.hasRead(book))
        book.author = "C"; XCTAssertFalse(model.hasRead(book))
        book.name = "Legacy"; XCTAssertTrue(model.hasRead(book))
    }

    func testFilterMatchesNameAuthorAndKindIgnoringCaseButNotIntro() {
        var book = SearchBook(); book.name = "Ocean"; book.author = "Writer"; book.kind = "Adventure"; book.intro = "Blocked"
        XCTAssertFalse(SearchResultFilter.allows(book, words: "\n OCE \n"))
        XCTAssertFalse(SearchResultFilter.allows(book, words: "writer"))
        XCTAssertFalse(SearchResultFilter.allows(book, words: "VENT"))
        XCTAssertTrue(SearchResultFilter.allows(book, words: "Blocked\n \n"))
    }

    func testSearchScopeRestrictsRequestsAndFilterRemainsReversible() async throws {
        let db = try AppDatabase.inMemory(), client = ReplayHttpClient()
        let sources = BookSourceRepository(database: db)
        for (host, enabled) in [("a", true), ("b", false)] {
            var source = BookSource(); source.bookSourceUrl = "https://\(host).test"; source.bookSourceName = host
            source.enabled = enabled; source.searchUrl = "/search"; source.ruleSearch = SearchRule()
            source.ruleSearch?.bookList = "tag.a"; source.ruleSearch?.name = "text"; source.ruleSearch?.bookUrl = "href"
            try await sources.insert(DiscoveryStorage.row(source, defaults: BookSourceRow()))
        }
        let url = URL(string: "https://b.test/search")!
        await client.enqueue(url: url, response: .init(status: 200, body: Data("<a href='/book'>Ocean</a>".utf8), finalURL: url))
        let model = SearchViewModel(sources: sources, client: client)
        model.scope = .init(value: "B::https://b.test")
        await model.search("Ocean")
        XCTAssertEqual(model.totalSources, 1); XCTAssertEqual(model.results.count, 1)
        model.filterWords = "Ocean"; XCTAssertTrue(model.visibleResults.isEmpty)
        model.filterWords = ""; XCTAssertEqual(model.visibleResults.count, 1)
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.url), [url])
        XCTAssertTrue(model.hasSearched)
        model.editQuery(); XCTAssertFalse(model.hasSearched)
    }
}
