import XCTest
import LegadoCore
@testable import AppCoreCheck

@MainActor
final class DiscoveryTests: XCTestCase {
    private let fixtures = URL(fileURLWithPath: #filePath)
        .resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/Conformance/fixtures/webbook")

    private func source(_ host: String = "https://example.invalid") throws -> BookSource {
        var value = try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: fixtures.appendingPathComponent("source.json")))
        value.bookSourceUrl = host
        return value
    }

    private func enqueue(_ client: ReplayHttpClient, host: String = "https://example.invalid", path: String, file: String) async throws {
        let url = URL(string: host + path)!
        await client.enqueue(url: url, response: HttpResponse(status: 200,
            body: try Data(contentsOf: fixtures.appendingPathComponent(file)), finalURL: url))
    }

    func testSearchAggregatesAndDeduplicatesSources() async throws {
        let db = try AppDatabase.inMemory()
        let sources = BookSourceRepository(database: db)
        let client = ReplayHttpClient()
        for host in ["https://example.invalid", "https://second.invalid"] {
            try await sources.upsert(DiscoveryStorage.row(source(host), defaults: BookSourceRow()))
            try await enqueue(client, host: host, path: "/search?key=demo&page=1", file: "search.html")
        }
        var disabled = try source("https://disabled.invalid"); disabled.enabled = false
        try await sources.upsert(DiscoveryStorage.row(disabled, defaults: BookSourceRow()))
        let model = SearchViewModel(sources: sources, client: client, concurrencyLimit: 1)
        await model.search("demo")
        XCTAssertEqual(model.results.count, 1)
        XCTAssertEqual(model.results.first?.sources.count, 2)
        XCTAssertEqual(model.completedSources, 2)
        XCTAssertFalse(model.isSearching)
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
        let item = try XCTUnwrap(model.results.first?.sources.first)
        var result = SearchResult(book: item)
        result.merge(item)
        XCTAssertEqual(result.sources.count, 1)
    }

    func testCancellationStopsPublishing() async throws {
        let db = try AppDatabase.inMemory()
        let sources = BookSourceRepository(database: db)
        try await sources.upsert(DiscoveryStorage.row(source(), defaults: BookSourceRow()))
        let client = SuspendedClient()
        let model = SearchViewModel(sources: sources, client: client)
        let task = Task { await model.search("demo") }
        await client.waitUntilStarted()
        model.cancel()
        await task.value
        XCTAssertFalse(model.isSearching)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertEqual(model.completedSources, 0)
    }

    func testConcurrencyLimitAndIncrementalResults() async throws {
        let db = try AppDatabase.inMemory()
        let sources = BookSourceRepository(database: db)
        let replay = ReplayHttpClient()
        for host in ["https://a.invalid", "https://b.invalid", "https://c.invalid"] {
            try await sources.upsert(DiscoveryStorage.row(source(host), defaults: BookSourceRow()))
            try await enqueue(replay, host: host, path: "/search?key=demo&page=1", file: "search.html")
        }
        let client = ControlledSearchClient(replay: replay)
        let model = SearchViewModel(sources: sources, client: client, concurrencyLimit: 2)
        let task = Task { await model.search("demo") }
        await client.waitForStarts(2)
        XCTAssertTrue(model.results.isEmpty)
        await client.release("a.invalid")
        await client.waitForStarts(3)
        XCTAssertEqual(model.completedSources, 1)
        XCTAssertEqual(model.results.first?.sources.count, 1)
        XCTAssertTrue(model.isSearching)
        await client.release("b.invalid")
        await client.release("c.invalid")
        await task.value
        let maximum = await client.maximumActive
        XCTAssertEqual(maximum, 2)
        XCTAssertEqual(model.results.first?.sources.count, 3)
    }

    func testCallerCancellationPropagates() async throws {
        let db = try AppDatabase.inMemory()
        let sources = BookSourceRepository(database: db)
        try await sources.upsert(DiscoveryStorage.row(source(), defaults: BookSourceRow()))
        let client = SuspendedClient()
        let model = SearchViewModel(sources: sources, client: client)
        let task = Task { await model.search("demo") }
        await client.waitUntilStarted()
        task.cancel()
        await task.value
        XCTAssertFalse(model.isSearching)
        XCTAssertTrue(model.results.isEmpty)
    }

    func testPerSourceTimeoutUsesInjectedClock() async throws {
        let db = try AppDatabase.inMemory()
        let sources = BookSourceRepository(database: db)
        try await sources.upsert(DiscoveryStorage.row(source(), defaults: BookSourceRow()))
        let client = SuspendedClient()
        let model = SearchViewModel(sources: sources, client: client, sourceTimeout: 12,
            timeoutSleep: { duration in
                XCTAssertEqual(duration, 12_000_000_000)
                await client.waitUntilStarted()
            })
        await model.search("demo")
        XCTAssertEqual(model.failedSources, 1)
        XCTAssertEqual(model.completedSources, 1)
        XCTAssertFalse(model.isSearching)
    }

    func testPrecisionSearchIsPassedToWebBook() async throws {
        let db = try AppDatabase.inMemory()
        let sources = BookSourceRepository(database: db)
        try await sources.upsert(DiscoveryStorage.row(source(), defaults: BookSourceRow()))
        let client = ReplayHttpClient()
        try await enqueue(client, path: "/search?key=demo&page=1", file: "search.html")
        let model = SearchViewModel(sources: sources, client: client)
        model.precisionSearch = true
        await model.search("demo")
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertEqual(model.failedSources, 0)
        XCTAssertEqual(model.completedSources, 1)
    }

    func testDetailsShelfPersistence() async throws {
        let db = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: db)
        let sources = BookSourceRepository(database: db)
        try await sources.upsert(DiscoveryStorage.row(source(), defaults: BookSourceRow()))
        let client = ReplayHttpClient()
        try await enqueue(client, path: "/book/1", file: "info.html")
        var result = SearchBook(now: 0)
        result.bookUrl = "https://example.invalid/book/1"; result.origin = "https://example.invalid"
        result.name = "航海记"; result.author = "林舟"
        let model = BookDetailViewModel(results: [result], sources: sources, bookshelf: shelf, client: client)
        await model.load()
        XCTAssertEqual(model.book?.intro, "一段合成的航海故事。")
        await model.toggleBookshelf()
        let saved = try await shelf.list()
        XCTAssertEqual(saved.map(\.name), ["航海记"])
        XCTAssertTrue(model.isOnBookshelf)
        await model.toggleBookshelf()
        let removed = try await shelf.list()
        XCTAssertTrue(removed.isEmpty)
        XCTAssertFalse(model.isOnBookshelf)
    }

    func testSwitchSourceAndPreserveStoredProgress() async throws {
        let db = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: db)
        let sources = BookSourceRepository(database: db)
        let client = ReplayHttpClient()
        var results: [SearchBook] = []
        for host in ["https://example.invalid", "https://second.invalid"] {
            try await sources.upsert(DiscoveryStorage.row(source(host), defaults: BookSourceRow()))
            try await enqueue(client, host: host, path: "/book/1", file: "info.html")
            var result = SearchBook(now: 0)
            result.bookUrl = host + "/book/1"; result.origin = host
            result.name = "航海记"; result.author = "林舟"
            results.append(result)
        }
        var existing = BookRow()
        existing.bookUrl = "https://second.invalid/book/1"; existing.origin = "https://second.invalid"
        existing.name = "航海记"; existing.author = "林舟"
        existing.durChapterIndex = 7; existing.durChapterPos = 25
        try await shelf.upsert(existing)
        let model = BookDetailViewModel(results: results, sources: sources, bookshelf: shelf, client: client)
        await model.load()
        await model.selectSource(1)
        XCTAssertEqual(model.book?.origin, "https://second.invalid")
        XCTAssertEqual(model.book?.durChapterIndex, 7)
        XCTAssertTrue(model.isOnBookshelf)
        await model.toggleBookshelf()
        await model.toggleBookshelf()
        let saved = try await shelf.get(bookUrl: existing.bookUrl)
        XCTAssertEqual(saved?.durChapterPos, 25)
    }

    func testTocPersistsAndReversesWithoutChangingIndexes() async throws {
        let db = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: db)
        let chapters = ChapterRepository(database: db)
        let client = ReplayHttpClient()
        try await enqueue(client, path: "/toc/1", file: "toc1.html")
        try await enqueue(client, path: "/toc/2", file: "toc2.html")
        var book = Book(now: 0)
        book.bookUrl = "https://example.invalid/book/1"; book.tocUrl = "https://example.invalid/toc/1"
        book.name = "航海记"; book.author = "林舟"; book.durChapterIndex = 1
        let model = TocViewModel(book: book, source: try source(), chapters: chapters, bookshelf: shelf, client: client, database: db)
        await model.refresh()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.displayedChapters.map(\.index), [0, 1])
        model.isReversed = true
        XCTAssertEqual(model.displayedChapters.map(\.index), [1, 0])
        XCTAssertEqual(model.currentChapterIndex, 1)
        let stored = try await chapters.list(bookUrl: book.bookUrl!)
        XCTAssertEqual(stored.map(\.title), ["启航", "归来"])
        XCTAssertTrue(stored[1].isVip)
        let visible = try await shelf.list()
        XCTAssertTrue(visible.isEmpty)
    }

    func testAlternativeSourceTocPreservesShelfAndProgress() async throws {
        let db = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: db)
        let chapters = ChapterRepository(database: db)
        var old = BookRow()
        old.bookUrl = "https://old.invalid/book/1"
        old.name = "航海记"; old.author = "林舟"
        old.durChapterIndex = 1; old.durChapterPos = 15; old.group = 4
        try await shelf.upsert(old)
        let client = ReplayHttpClient()
        try await enqueue(client, path: "/toc/1", file: "toc1.html")
        try await enqueue(client, path: "/toc/2", file: "toc2.html")
        var book = Book(now: 0)
        book.bookUrl = "https://example.invalid/book/1"; book.tocUrl = "https://example.invalid/toc/1"
        book.name = old.name; book.author = old.author
        let model = TocViewModel(book: book, source: try source(), chapters: chapters, bookshelf: shelf, client: client, database: db)
        await model.refresh()
        XCTAssertNil(model.errorMessage)
        let visible = try await shelf.list()
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.bookUrl, book.bookUrl)
        XCTAssertEqual(visible.first?.durChapterPos, 15)
        XCTAssertEqual(visible.first?.group, 4)
        XCTAssertEqual(model.currentChapterIndex, 1)
        let stored = try await chapters.list(bookUrl: book.bookUrl!)
        XCTAssertEqual(stored.count, 2)
    }
}

private actor SuspendedClient: HttpClient {
    private var started = false
    private var waiter: CheckedContinuation<Void, Never>?

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        started = true
        waiter?.resume(); waiter = nil
        try await Task.sleep(nanoseconds: 60_000_000_000)
        throw URLError(.timedOut)
    }
}

private actor ControlledSearchClient: HttpClient {
    let replay: ReplayHttpClient
    private var continuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var startCount = 0
    private var active = 0
    private(set) var maximumActive = 0
    private var waiter: (Int, CheckedContinuation<Void, Never>)?

    init(replay: ReplayHttpClient) { self.replay = replay }

    func waitForStarts(_ count: Int) async {
        if startCount >= count { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }

    func release(_ host: String) {
        continuations.removeValue(forKey: host)?.resume()
    }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        startCount += 1
        active += 1
        maximumActive = max(maximumActive, active)
        await withCheckedContinuation { continuation in
            continuations[request.url.host!] = continuation
            if let current = waiter, startCount >= current.0 {
                waiter = nil
                current.1.resume()
            }
        }
        active -= 1
        return try await replay.send(request)
    }
}
