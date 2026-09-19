import XCTest
import LegadoCore
@testable import BookshelfAdvancedCheck

@MainActor
final class BookshelfBookListTests: XCTestCase {
    func testStrictValidationDeduplicationAndExportSchema() throws {
        let entries = try BookshelfBookList.decode(Data(#"[{"name":"Book","author":null},{"name":"Book"},{"name":"Book","author":"Writer"}]"#.utf8))
        XCTAssertEqual(entries, [.init(name: "Book", author: ""), .init(name: "Book", author: "Writer")])
        for text in ["{}", "[null]", #"[{"name":1}]"#, #"[{"name":" "}]"#, #"[{"name":"Book","author":false}]"#] {
            XCTAssertThrowsError(try BookshelfBookList.decode(Data(text.utf8)))
        }
        var book = BookRow(); book.name = "Book"; book.author = "Writer"; book.intro = "Original"; book.customIntro = "Custom"
        book.bookUrl = "private-book-url"; book.origin = "private-source"
        let data = try BookshelfBookList.encode([book])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: String]])
        XCTAssertEqual(json, [["name": "Book", "author": "Writer", "intro": "Custom"]])
        XCTAssertEqual(try BookshelfBookList.decode(data), [.init(name: "Book", author: "Writer")])
        XCTAssertThrowsError(try BookshelfBookList.decode(Data(repeating: 32, count: BookshelfBookList.maximumBytes + 1)))
    }

    func testImportSkipsExistingAndFallsBackEnabledSourcesWithoutFetchingDetails() async throws {
        let db = try AppDatabase.inMemory(), client = ReplayHttpClient()
        var existing = BookRow(); existing.name = "Existing"; existing.author = "Writer"; existing.bookUrl = "saved"
        existing.customCoverUrl = "keep"; existing.durChapterPos = 45; existing.group = 2
        try await BookshelfRepository(database: db).insert(existing)
        for (order, host, enabled) in [(0, "disabled", false), (1, "empty", true), (2, "match", true)] {
            var source = BookSource(); source.bookSourceUrl = "https://\(host).test"; source.bookSourceName = host
            source.customOrder = order; source.enabled = enabled; source.searchUrl = "/search"
            source.ruleSearch = SearchRule(); source.ruleSearch?.bookList = "tag.a"; source.ruleSearch?.name = "text"
            source.ruleSearch?.author = "data-author"; source.ruleSearch?.bookUrl = "href"
            try await BookSourceRepository(database: db).insert(DiscoveryStorage.row(source, defaults: BookSourceRow()))
        }
        for (host, html) in [("empty", "<p>No match</p>"), ("match", "<a href='/book' data-author='Writer'>New</a>")] {
            let url = URL(string: "https://\(host).test/search")!
            await client.enqueue(url: url, response: .init(status: 200, body: Data(html.utf8), finalURL: url))
        }
        let model = BookshelfBookListModel(database: db, client: client, concurrency: 2)
        model.input = #"[{"name":"Existing","author":"Writer"},{"name":"New","author":"Writer"},{"name":"New","author":"Writer"}]"#
        await model.importBooks(groupID: 4)
        XCTAssertEqual(model.total, 2); XCTAssertEqual(model.completed, 2); XCTAssertEqual(model.failures, [])
        let stored = try await BookshelfRepository(database: db).all()
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.first { $0.name == "New" }?.group, 4)
        XCTAssertEqual(stored.first { $0.name == "Existing" }?.durChapterPos, 45)
        XCTAssertEqual(stored.first { $0.name == "Existing" }?.group, 2)
        XCTAssertEqual(stored.first { $0.name == "Existing" }?.customCoverUrl, "keep")
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.url.absoluteString), ["https://empty.test/search", "https://match.test/search"])
    }

    func testURLImportAndNoMatchReport() async throws {
        let db = try AppDatabase.inMemory(), client = ReplayHttpClient()
        let url = URL(string: "https://list.test/books.json")!
        await client.enqueue(url: url, response: .init(status: 200, body: Data(#"[{"name":"Missing"}]"#.utf8), finalURL: url))
        let model = BookshelfBookListModel(database: db, client: client)
        model.input = url.absoluteString
        await model.importBooks(groupID: -1)
        XCTAssertEqual(model.completed, 1); XCTAssertEqual(model.failures.count, 1)
        XCTAssertTrue(model.failures[0].contains("Missing"))
        XCTAssertFalse(model.isImporting)
    }

    func testCancelledImportDoesNotSaveOrContinueSources() async throws {
        let db = try AppDatabase.inMemory(), client = ReplayHttpClient()
        let model = BookshelfBookListModel(database: db, client: client)
        model.input = #"[{"name":"New"}]"#
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; await model.importBooks(groupID: 1) }
        await task.value
        let stored = try await BookshelfRepository(database: db).all(), requests = await client.requests
        XCTAssertTrue(stored.isEmpty); XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(model.completed, 0); XCTAssertFalse(model.isImporting)
    }

    func testLogStoreBoundsAndClear() {
        let store = AppLogStore(capacity: 2)
        store.append("First"); store.append("Second"); store.append(String(repeating: "x", count: 3000))
        XCTAssertEqual(store.snapshot().count, 2)
        XCTAssertEqual(store.snapshot().first?.message, "Second")
        XCTAssertEqual(store.snapshot().last?.message.count, 2048)
        store.clear(); XCTAssertTrue(store.snapshot().isEmpty)
    }

    func testNetworkCancellationStopsImportWithoutFailureOrNextSource() async throws {
        let db = try AppDatabase.inMemory(), client = ReplayHttpClient()
        for (order, host) in [(0, "first"), (1, "second")] {
            var source = BookSource(); source.bookSourceUrl = "https://\(host).test"; source.searchUrl = "/search"
            source.customOrder = order; source.ruleSearch = SearchRule(); source.ruleSearch?.bookList = "tag.a"
            try await BookSourceRepository(database: db).insert(DiscoveryStorage.row(source, defaults: BookSourceRow()))
        }
        await client.enqueue(url: URL(string: "https://first.test/search")!, error: URLError(.cancelled))
        let model = BookshelfBookListModel(database: db, client: client, concurrency: 1)
        model.input = #"[{"name":"First"},{"name":"Second"}]"#
        await model.importBooks(groupID: 0)
        XCTAssertEqual(model.completed, 0); XCTAssertEqual(model.failures, [])
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertFalse(model.isImporting)
    }
}
