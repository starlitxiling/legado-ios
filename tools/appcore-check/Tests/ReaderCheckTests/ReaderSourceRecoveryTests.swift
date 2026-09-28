import XCTest
import LegadoCore
@testable import ReaderCheck

@MainActor
final class ReaderSourceRecoveryTests: XCTestCase {
    func testNormalizedOriginIsSavedOnlyForUniqueMatch() async throws {
        for suffix in ["/", " ", "#yc1101b", "/#yc1101b", ""] {
            let database = try AppDatabase.inMemory()
            let repository = BookSourceRepository(database: database)
            var source = BookSourceRow(); source.bookSourceUrl = "https://example.test/path" + (suffix.isEmpty ? "/" : ""); source.bookSourceName = "Resolved source"
            try await repository.insert(source)
            var book = BookRow(); book.bookUrl = "fixture:book"; book.origin = suffix.isEmpty ? "https://example.test/path" : " HTTPS://EXAMPLE.TEST/path" + suffix
            try await BookshelfRepository(database: database).insert(book)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let model = ReaderViewModel(database: database, client: ReplayHttpClient(), cacheDirectory: root, preDownloadCount: { 0 })
            await model.load(bookURL: book.bookUrl)
            let saved = try await BookshelfRepository(database: database).get(bookUrl: book.bookUrl)
            let matched = try await repository.resolveForBookOrigin(book.origin)
            XCTAssertEqual(matched?.bookSourceUrl, source.bookSourceUrl)
            XCTAssertEqual(saved?.origin, source.bookSourceUrl)
            XCTAssertEqual(saved?.originName, source.bookSourceName)
            await model.close()
        }
        let database = try AppDatabase.inMemory()
        let repository = BookSourceRepository(database: database)
        for url in ["https://example.test", "https://example.test/"] {
            var source = BookSourceRow(); source.bookSourceUrl = url; try await repository.insert(source)
        }
        let ambiguous = try await repository.resolveForBookOrigin("https://example.test#fragment")
        XCTAssertNil(ambiguous)
        let exact = try await repository.resolveForBookOrigin("https://example.test/")
        XCTAssertEqual(exact?.bookSourceUrl, "https://example.test/")
    }

    func testExistingSourceServerFailureDoesNotStartRecovery() async throws {
        let database = try AppDatabase.inMemory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var book = BookRow(); book.bookUrl = "https://old.test/book"; book.origin = "https://old.test"
        try await BookshelfRepository(database: database).insert(book)
        var chapter = BookChapterRow(); chapter.bookUrl = book.bookUrl; chapter.url = "https://old.test/chapter"; chapter.title = "Chapter"
        try await ChapterRepository(database: database).replaceAll(bookUrl: book.bookUrl, chapters: [chapter])
        var source = BookSourceRow(); source.bookSourceUrl = book.origin; source.ruleContent = #"{"content":"tag.p"}"#
        try await BookSourceRepository(database: database).insert(source)
        let client = ReplayHttpClient()
        let url = URL(string: chapter.url)!
        await client.enqueue(url: url, response: .init(status: 503, body: Data(), finalURL: url))
        let model = ReaderViewModel(database: database, client: client, cacheDirectory: root, preDownloadCount: { 0 })
        model.autoChangeSource = { true }
        await model.load(bookURL: book.bookUrl)
        XCTAssertNil(model.sourceRecoveryTask)
        XCTAssertNil(model.recoveringMessage)
        XCTAssertTrue(model.userError?.actions.contains(.changeSource) == true)
        XCTAssertEqual(model.book?.origin, book.origin)
        await model.close()
    }

    func testRecoveryDeadlineReturnsEvenWhenClientIgnoresCancellation() async throws {
        let client = RecoveryRequestGate()
        var source = BookSource(); source.bookSourceUrl = "https://slow.test"
        source.searchUrl = "https://slow.test/search"
        var book = Book(); book.name = "Timeout"
        let finished = expectation(description: "Recovery deadline returns")
        let task = Task {
            defer { finished.fulfill() }
            do {
                _ = try await ReaderSourceRecovery.find(book: book, chapterIndex: 0, chapterTitle: "",
                    sources: [source], client: client, configuration: .init(),
                    waitForTimeout: { await client.waitUntilRequested() })
                XCTFail("Expected deadline failure")
            } catch {
                guard case ReaderSourceRecoveryError.timedOut = error else {
                    XCTFail("Unexpected error: \(error)"); return
                }
            }
        }
        await fulfillment(of: [finished], timeout: 2)
        await client.release()
        await task.value
    }

    func testNoCandidatesFailsWithoutStartingDeadlineOrNetwork() async throws {
        do {
            _ = try await ReaderSourceRecovery.find(book: Book(), chapterIndex: 0, chapterTitle: "", sources: [],
                client: ReplayHttpClient(), configuration: .init(), waitForTimeout: { XCTFail("No timer needed") })
            XCTFail("Expected no candidates")
        } catch {
            guard case ReaderSourceRecoveryError.noCandidates = error else { XCTFail("Unexpected error: \(error)"); return }
        }
    }

    func testSlowRecoveryNeverBlocksReaderAndCloseCancelsIt() async throws {
        let database = try AppDatabase.inMemory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var row = BookRow(); row.bookUrl = "https://missing.test/book"; row.origin = "https://missing.test"
        row.name = "Missing"; row.type = 0
        try await BookshelfRepository(database: database).insert(row)
        var source = BookSourceRow(); source.bookSourceUrl = "https://slow.test"; source.searchUrl = "https://slow.test/search"
        try await BookSourceRepository(database: database).insert(source)
        let client = RecoveryRequestGate()
        let model = ReaderViewModel(database: database, client: client, cacheDirectory: root, preDownloadCount: { 0 })
        model.autoChangeSource = { true }
        await model.load(bookURL: row.bookUrl)
        XCTAssertTrue(model.acceptsInput)
        XCTAssertNotNil(model.pagination)
        let recovery = model.sourceRecoveryTask
        await client.waitUntilRequested()
        XCTAssertFalse(model.isLoading)
        XCTAssertNotNil(model.recoveringMessage)
        await model.close()
        XCTAssertNil(model.recoveringMessage)
        await client.release()
        await recovery?.value
        XCTAssertEqual(model.book?.origin, row.origin)
        let saved = try await BookshelfRepository(database: database).get(bookUrl: row.bookUrl)
        XCTAssertNotNil(saved)
    }

    func testMissingSourceShowsPlaceholderWithoutWaitingForRecovery() async throws {
        let database = try AppDatabase.inMemory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var row = BookRow(); row.bookUrl = "https://missing.test/book"; row.origin = "https://missing.test"
        row.name = "Missing"; row.durChapterPos = 37
        try await BookshelfRepository(database: database).insert(row)
        let model = ReaderViewModel(database: database, client: ReplayHttpClient(), cacheDirectory: root, preDownloadCount: { 0 })
        await model.load(bookURL: row.bookUrl)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.acceptsInput)
        XCTAssertEqual(model.book?.bookUrl, row.bookUrl)
        XCTAssertTrue(model.pagination?.text.string.contains("没有书源") == true)
        await model.reflow(size: CGSize(width: 300, height: 500))
        XCTAssertTrue(model.pagination?.text.string.contains("没有书源") == true)
        await model.saveProgress()
        let saved = try await BookshelfRepository(database: database).get(bookUrl: row.bookUrl)
        XCTAssertEqual(saved?.durChapterPos, 37)
        await model.close()
    }

    func testFailedContentSwitchesOnlyAfterReplacementChapterLoads() async throws {
        let database = try AppDatabase.inMemory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var row = BookRow(); row.bookUrl = "https://old.test/book"; row.origin = "https://old.test"
        row.name = "Recovery"; row.author = "Author"; row.group = 4
        try await BookshelfRepository(database: database).insert(row)
        var chapter = BookChapterRow(); chapter.bookUrl = row.bookUrl; chapter.url = "https://old.test/chapter"; chapter.title = "Chapter"
        try await ChapterRepository(database: database).replaceAll(bookUrl: row.bookUrl, chapters: [chapter])
        var source = BookSourceRow(); source.bookSourceUrl = "https://new.test"; source.bookSourceName = "Replacement"
        source.mainJs = """
        function search(key) { return [{name:key,author:'Author',bookUrl:baseUrl+'/book'}]; }
        function getBookInfo() { return {tocUrl:baseUrl+'/toc'}; }
        function getChapters() { return [{title:'Chapter',url:baseUrl+'/chapter'}]; }
        function getContent() { return 'Recovered body'; }
        """
        try await BookSourceRepository(database: database).upsert([source])
        let model = ReaderViewModel(database: database, client: ReplayHttpClient(), cacheDirectory: root, preDownloadCount: { 0 })
        model.autoChangeSource = { false }
        await model.load(bookURL: row.bookUrl)
        XCTAssertEqual(model.book?.bookUrl, row.bookUrl)
        XCTAssertNotNil(model.errorMessage)
        model.autoChangeSource = { true }
        await model.retry()
        await model.sourceRecoveryTask?.value
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.book?.origin, "https://new.test")
        XCTAssertEqual(model.book?.group, 4)
        XCTAssertTrue(model.pagination?.text.string.contains("Recovered body") == true)
        let old = try await BookshelfRepository(database: database).get(bookUrl: row.bookUrl)
        XCTAssertNil(old)
        await model.close()
    }

    func testUnusableCandidatesLeaveOriginalBookIntact() async throws {
        let database = try AppDatabase.inMemory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var row = BookRow(); row.bookUrl = "https://old.test/book"; row.origin = "https://old.test"; row.name = "Recovery"
        try await BookshelfRepository(database: database).insert(row)
        var source = BookSourceRow(); source.bookSourceUrl = "https://empty.test"
        source.mainJs = """
        function search(key) { return [{name:key,author:'',bookUrl:baseUrl+'/book'}]; }
        function getBookInfo() { return {tocUrl:baseUrl+'/toc'}; }
        function getChapters() { return [{title:'Chapter',url:baseUrl+'/chapter'}]; }
        function getContent() { throw 'Unavailable content'; }
        """
        try await BookSourceRepository(database: database).upsert([source])
        let model = ReaderViewModel(database: database, client: ReplayHttpClient(), cacheDirectory: root, preDownloadCount: { 0 })
        model.autoChangeSource = { true }
        await model.load(bookURL: row.bookUrl)
        await model.sourceRecoveryTask?.value
        XCTAssertNotNil(model.errorMessage)
        let saved = try await BookshelfRepository(database: database).get(bookUrl: row.bookUrl)
        XCTAssertNotNil(saved)
        XCTAssertTrue(model.pagination?.text.string.contains("没有书源") == true)
        await model.close()
    }
}

private actor RecoveryRequestGate: HttpClient {
    private var continuation: CheckedContinuation<HttpResponse, Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var requested = false
    private var released = false

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        requested = true
        waiters.forEach { $0.resume() }; waiters = []
        if released { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        if requested || released { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        released = true
        continuation?.resume(throwing: CancellationError()); continuation = nil
        waiters.forEach { $0.resume() }; waiters = []
    }
}
