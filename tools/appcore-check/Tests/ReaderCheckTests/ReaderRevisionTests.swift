import XCTest
import LegadoCore
@testable import ReaderCheck

@MainActor
final class ReaderRevisionTests: XCTestCase {
    private func fixture(count: Int = 3, savedIndex: Int = 0, savedOffset: Int = 0) async throws -> (AppDatabase, BookRow, URL) {
        let db = try AppDatabase.inMemory()
        var book = BookRow(); book.bookUrl = "https://revision.test/book"; book.origin = "https://revision.test"
        book.durChapterIndex = savedIndex; book.durChapterPos = savedOffset
        try await BookshelfRepository(database: db).insert(book)
        var source = BookSourceRow(); source.bookSourceUrl = book.origin; source.ruleContent = #"{"content":"tag.p@text"}"#
        try await BookSourceRepository(database: db).insert(source)
        for index in 0..<count {
            var chapter = BookChapterRow(); chapter.bookUrl = book.bookUrl; chapter.index = index
            chapter.url = "https://revision.test/\(index)"; chapter.title = "第\(index)章"
            try await ChapterRepository(database: db).insert(chapter)
        }
        return (db, book, FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func enqueue(_ client: ReplayHttpClient, index: Int, long: Bool = false) async {
        let url = URL(string: "https://revision.test/\(index)")!
        let html = String(repeating: "<p>甲乙丙丁戊己庚辛壬癸。</p>", count: long ? 200 : 1)
        await client.enqueue(url: url, response: .init(status: 200, body: Data(html.utf8), finalURL: url))
    }

    func testRetryFailedJumpAndInitialRestore() async throws {
        let (db, book, directory) = try await fixture(savedIndex: 2, savedOffset: 90)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient()
        await client.enqueue(url: URL(string: "https://revision.test/2")!, error: URLError(.notConnectedToInternet))
        let model = ReaderViewModel(database: db, client: client, cacheDirectory: directory, now: { 1 })
        await model.load(bookURL: book.bookUrl)
        XCTAssertNotNil(model.errorMessage)
        await enqueue(client, index: 2, long: true)
        await model.retry()
        XCTAssertEqual(model.chapterIndex, 2, "重试必须保留初次恢复的章节")
        XCTAssertEqual(model.characterOffset, 90, "重试必须保留初次恢复的偏移")
        await model.waitForPrefetch()
        await client.enqueue(url: URL(string: "https://revision.test/1")!, error: URLError(.notConnectedToInternet))
        await model.goToChapter(1, lastPage: true)
        XCTAssertNotNil(model.errorMessage)
        await enqueue(client, index: 1, long: true)
        await model.retry()
        XCTAssertEqual(model.chapterIndex, 1, "重试必须重放失败的跳章")
        XCTAssertEqual(model.pageIndex, (model.pagination?.pages.count ?? 0) - 1)
        let saved = try await BookshelfRepository(database: db).get(bookUrl: book.bookUrl)
        XCTAssertEqual(saved?.durChapterIndex, 1)
        await model.close()
    }

    func testThreeReflowsKeepReadingAnchor() async throws {
        let (db, book, directory) = try await fixture(count: 1)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient(); await enqueue(client, index: 0, long: true)
        let model = ReaderViewModel(database: db, client: client, cacheDirectory: directory, now: { 1 })
        await model.load(bookURL: book.bookUrl); await model.selectPage(3)
        let anchor = model.characterOffset
        for size in [27.0, 19.0, 31.0] {
            var settings = ReaderSettings(); settings.textSize = size
            await model.reflow(settings: settings)
            XCTAssertEqual(model.characterOffset, anchor, "连续重排不得改变阅读字符锚点")
            XCTAssertEqual(model.pageIndex, model.pagination?.pageIndex(at: anchor))
        }
        let saved = try await BookshelfRepository(database: db).get(bookUrl: book.bookUrl)
        XCTAssertEqual(saved?.durChapterPos, anchor)
        await model.close()
    }

    func testAndroidIndentedTextOffset() async throws {
        let (db, book, directory) = try await fixture(count: 1, savedOffset: 368)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient(); await enqueue(client, index: 0, long: true)
        let model = ReaderViewModel(database: db, client: client, cacheDirectory: directory, now: { 1 })
        await model.load(bookURL: book.bookUrl)
        let androidText = "第0章\n" + Array(repeating: "　　甲乙丙丁戊己庚辛壬癸。", count: 200).joined(separator: "\n")
        XCTAssertEqual(model.pagination?.text.string, androidText, "缩进必须进入持久化偏移坐标系")
        let expected = try Paginator().paginate(title: "第0章", paragraphs: Array(repeating: "　　甲乙丙丁戊己庚辛壬癸。", count: 200),
            size: CGSize(width: 320, height: 480), settings: .init())
        XCTAssertEqual(model.pageIndex, expected.pageIndex(at: 368))
        XCTAssertEqual(model.characterOffset, 368)
        // 标题含换行占 4 个 UTF-16 单元，前 26 段各占 14 个，固定偏移位于第 27 段开头。
        XCTAssertEqual((androidText as NSString).substring(with: NSRange(location: 368, length: 3)), "　　甲")
        await model.close()
    }

    func testLayoutRunsOffMainAndCoalescesSettings() async throws {
        let (db, book, directory) = try await fixture(count: 1)
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = LayoutProbe()
        let barrier = LayoutBarrier()
        let client = ReplayHttpClient(); await enqueue(client, index: 0, long: true)
        let model = ReaderViewModel(database: db, client: client, cacheDirectory: directory, now: { 1 },
            layoutDidStart: { probe.record() }, waitForLayoutDebounce: { await barrier.wait() })
        await model.load(bookURL: book.bookUrl)
        XCTAssertFalse(probe.mainThreadSeen, "正文处理与分页不能占用主线程")
        probe.reset()
        let tasks = (21...25).map { value in
            Task { @MainActor in
                var settings = ReaderSettings(); settings.textSize = Double(value)
                await model.reflow(settings: settings)
            }
        }
        for task in tasks { await task.value }
        XCTAssertFalse(probe.mainThreadSeen)
        XCTAssertEqual(probe.count, 1, "连续设置必须合并为最后一次分页")
        XCTAssertEqual(model.settings.textSize, 25)
        await model.close()
    }

    func testObsoleteDownloadCancelledAfterJump() async throws {
        let (db, book, directory) = try await fixture(count: 4)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = SuspendedChapterClient()
        let model = ReaderViewModel(database: db, client: client, cacheDirectory: directory, now: { 1 })
        await model.load(bookURL: book.bookUrl)
        await client.waitForBlockedRequest()
        await model.goToChapter(2)
        await model.goToChapter(3)
        let cancelled = await client.wasCancelled
        XCTAssertTrue(cancelled, "离开章节必须取消真实的正文下载")
        XCTAssertEqual(model.chapterIndex, 3)
        await model.close()
    }

    func testForegroundDownloadCanBeSupersededByAnotherJump() async throws {
        let (db, book, directory) = try await fixture(count: 4)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = SuspendedChapterClient()
        let model = ReaderViewModel(database: db, client: client, cacheDirectory: directory, now: { 1 })
        await model.load(bookURL: book.bookUrl)
        await client.waitForBlockedRequest()
        let firstJump = Task { await model.goToChapter(1) }
        await client.waitForBlockedRequest(minimumCount: 2)
        XCTAssertTrue(model.isLoading)
        await model.goToChapter(2)
        await firstJump.value
        let cancellations = await client.cancellationCount
        XCTAssertEqual(cancellations, 2)
        XCTAssertEqual(model.chapterIndex, 2)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        await model.close()
    }

    func testCachedBodyUsesRenamedDirectoryTitle() async throws {
        let (db, book, directory) = try await fixture(count: 1)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient(); await enqueue(client, index: 0)
        let model = ReaderViewModel(database: db, client: client, cacheDirectory: directory, now: { 1 })
        await model.load(bookURL: book.bookUrl)
        let storedChapter = try await ChapterRepository(database: db).get(bookUrl: book.bookUrl, index: 0)
        var chapter = try XCTUnwrap(storedChapter)
        chapter.title = "目录里的新章名"
        try await ChapterRepository(database: db).update(chapter)
        await model.goToChapter(0)
        XCTAssertEqual(model.chapterTitle, "目录里的新章名")
        await model.close()
        let reopened = ReaderViewModel(database: db, client: client, cacheDirectory: directory, now: { 1 })
        await reopened.load(bookURL: book.bookUrl)
        XCTAssertEqual(reopened.chapterTitle, "目录里的新章名")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(files.first))) as? [String: Any]
        XCTAssertNil(object?["chapter"], "正文缓存不得保存章节元数据")
        await reopened.close()
    }

    func testCancellingOneCacheConsumerKeepsSharedDownload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ReaderChapterCache(directory: directory)
        let client = SuspendedChapterClient()
        var book = Book(now: 0); book.bookUrl = "https://revision.test/book"
        var chapter = BookChapter(); chapter.url = "https://revision.test/1"; chapter.bookUrl = book.bookUrl
        var source = BookSource(); source.bookSourceUrl = "https://revision.test"
        var rule = ContentRule(); rule.content = "tag.p@text"; source.ruleContent = rule
        let inputBook = book, inputChapter = chapter, inputSource = source
        let first = Task { try await cache.content(book: inputBook, chapter: inputChapter, nextURL: nil, source: inputSource, client: client) }
        await client.waitForBlockedRequest()
        let second = Task { try await cache.content(book: inputBook, chapter: inputChapter, nextURL: nil, source: inputSource, client: client) }
        while await cache.pendingConsumerCount != 2 { await Task.yield() }
        first.cancel()
        do { _ = try await first.value; XCTFail("取消的消费者不应收到正文") }
        catch { XCTAssertTrue(error is CancellationError) }
        let cancelled = await client.wasCancelled
        XCTAssertFalse(cancelled, "仍有消费者时不得取消共享下载")
        await client.finishBlockedRequests()
        let result = try await second.value
        XCTAssertTrue(result.rawContent.contains("共享正文"))
    }
}

private final class LayoutProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var onMain = false
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    var mainThreadSeen: Bool { lock.lock(); defer { lock.unlock() }; return onMain }
    func record() { lock.lock(); defer { lock.unlock() }; calls += 1; onMain = onMain || Thread.isMainThread }
    func reset() { lock.lock(); defer { lock.unlock() }; calls = 0; onMain = false }
}

private actor LayoutBarrier {
    private var initialLoad = true
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if initialLoad { initialLoad = false; return }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if waiting.count == 5 {
                for continuation in waiting { continuation.resume() }
                waiting.removeAll()
            }
        }
    }
}

private actor SuspendedChapterClient: HttpClient {
    private var blocked: [UUID: CheckedContinuation<HttpResponse, Error>] = [:]
    private var started = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var cancellationCount = 0
    var wasCancelled: Bool { cancellationCount > 0 }
    func waitForBlockedRequest(minimumCount: Int = 1) async {
        if started >= minimumCount { return }
        await withCheckedContinuation { waiters.append((minimumCount, $0)) }
    }
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        if request.url.lastPathComponent != "1" {
            return .init(status: 200, body: Data("<p>正文</p>".utf8), finalURL: request.url)
        }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation {
                blocked[id] = $0; started += 1
                for (count, waiter) in waiters where started >= count { waiter.resume() }
                waiters.removeAll(where: { started >= $0.0 })
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }
    private func cancel(id: UUID) {
        cancellationCount += 1
        blocked.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
    func finishBlockedRequests() {
        for continuation in blocked.values {
            continuation.resume(returning: .init(status: 200, body: Data("<p>共享正文</p>".utf8),
                finalURL: URL(string: "https://revision.test/1")!))
        }
        blocked.removeAll()
    }
}
