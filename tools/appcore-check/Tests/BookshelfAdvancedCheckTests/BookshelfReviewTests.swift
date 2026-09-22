import XCTest
import CryptoKit
import LegadoCore
@testable import BookshelfAdvancedCheck

@MainActor
final class BookshelfReviewTests: XCTestCase {
    func testRefreshCallbacksTrackEligibleBooksAndFailures() async throws {
        actor Events {
            var prepared: [String] = []
            var completed: [String] = []
            func prepare(_ urls: [String]) { prepared = urls }
            func complete(_ url: String) { completed.append(url) }
        }
        let database = try AppDatabase.inMemory()
        var remote = BookRow(); remote.bookUrl = "remote"; remote.name = "Remote"; remote.origin = "missing"
        var local = BookRow(); local.bookUrl = "local"; local.name = "Local"; local.origin = "loc_book"; local.type = 256
        var disabled = BookRow(); disabled.bookUrl = "disabled"; disabled.name = "Disabled"; disabled.canUpdate = false
        let rows = [remote, local, disabled]
        try await BookshelfRepository(database: database).upsert(rows)
        let events = Events()
        let report = try await BookshelfRefreshService.refresh(database: database, client: ReplayHttpClient(), rows: rows,
            onPrepared: { await events.prepare($0) }, onCompleted: { await events.complete($0) })
        let prepared = await events.prepared, completed = await events.completed
        XCTAssertEqual(prepared, ["remote"])
        XCTAssertEqual(completed, ["remote"])
        XCTAssertEqual(report.failures.map(\.bookURL), ["remote"])
        let model = DownloadCenterModel(database: database, client: ReplayHttpClient())
        await model.refresh(rows)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertTrue(model.refreshingBookURLs.isEmpty)
    }

    func testStoppingRefreshCancelsRequestWithoutFailureAndAllowsRestart() async throws {
        let database = try AppDatabase.inMemory()
        var source = BookSourceRow(); source.bookSourceUrl = "https://refresh.test"
        source.ruleToc = #"{"chapterList":"tag.a","chapterName":"text","chapterUrl":"href"}"#
        try await BookSourceRepository(database: database).insert(source)
        var row = BookRow(); row.bookUrl = "https://refresh.test/book"; row.tocUrl = "https://refresh.test/toc"
        row.origin = source.bookSourceUrl; row.name = "Book"
        try await BookshelfRepository(database: database).insert(row)
        let started = expectation(description: "request started")
        let client = StoppingRefreshClient(started: { started.fulfill() })
        let model = DownloadCenterModel(database: database, client: client)
        let refresh = Task { await model.refresh([row]) }
        await fulfillment(of: [started], timeout: 5)
        XCTAssertTrue(model.isRefreshing)
        XCTAssertEqual(model.refreshTotal, 1)
        XCTAssertEqual(model.refreshCompleted, 0)
        model.stopRefresh()
        await refresh.value
        XCTAssertFalse(model.isRefreshing)
        XCTAssertTrue(model.refreshingBookURLs.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.refreshReport?.cancelled, true)
        XCTAssertEqual(model.refreshReport?.failures.count, 0)
        await model.refresh([])
        XCTAssertEqual(model.refreshTotal, 0)
        XCTAssertEqual(model.refreshReport?.cancelled, false)
    }

    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!

    func testPreUpdateMigratesBookURLAndPersistsRefreshedToc() async throws {
        let database = try AppDatabase.inMemory()
        var source = BookSource()
        source.bookSourceUrl = "https://refresh.test"
        source.searchUrl = "/search"
        source.ruleSearch = SearchRule()
        source.ruleSearch?.bookList = "tag.a"; source.ruleSearch?.name = "text"
        source.ruleSearch?.author = "data-author"; source.ruleSearch?.bookUrl = "href"
        source.ruleBookInfo = BookInfoRule(); source.ruleBookInfo?.tocUrl = "tag.nav@data-url"
        source.ruleToc = TocRule(); source.ruleToc?.preUpdateJs = "java.reGetBook()"
        source.ruleToc?.chapterList = "tag.a"; source.ruleToc?.chapterName = "text"; source.ruleToc?.chapterUrl = "href"
        try await BookSourceRepository(database: database).insert(DiscoveryStorage.row(source, defaults: BookSourceRow()))
        var book = BookRow()
        book.bookUrl = "https://refresh.test/old"; book.tocUrl = "https://refresh.test/old-toc"
        book.origin = source.bookSourceUrl!; book.name = "Book"; book.author = "Author"; book.durChapterPos = 12
        try await BookshelfRepository(database: database).insert(book)
        let client = ReplayHttpClient()
        for (path, body) in [("/search", "<a href='/new' data-author='Author'>Book</a>"),
                             ("/new", "<nav data-url='/new-toc'></nav>"), ("/new-toc", "<a href='/chapter'>Chapter</a>")] {
            let url = URL(string: "https://refresh.test" + path)!
            await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data(body.utf8), finalURL: url))
        }
        _ = try await BookshelfRefreshService.refresh(database: database, client: client, rows: [book])
        let stored = try await BookshelfRepository(database: database).get(bookUrl: "https://refresh.test/new")
        let updated = try XCTUnwrap(stored)
        XCTAssertEqual(updated.tocUrl, "https://refresh.test/new-toc")
        XCTAssertEqual(updated.durChapterPos, 12)
        let old = try await BookshelfRepository(database: database).get(bookUrl: book.bookUrl)
        XCTAssertNil(old)
        let chapters = try await ChapterRepository(database: database).list(bookUrl: updated.bookUrl)
        XCTAssertEqual(chapters.map(\.title), ["Chapter"])
    }

    func testLocalDownloadStillWritesPortableContentCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("local.txt")
        try "Body text".write(to: file, atomically: true, encoding: .utf8)
        let parsed = try LocalBook.parse(url: file)
        let database = try AppDatabase.inMemory()
        try await LocalBook.save(book: parsed.book, chapters: parsed.chapters, database: database)
        let stored = try await BookshelfRepository(database: database).get(bookUrl: parsed.book.bookUrl ?? "")
        let row = try XCTUnwrap(stored)
        let cache = directory.appendingPathComponent("cache")
        let model = DownloadCenterModel(database: database, client: ReplayHttpClient(), directory: cache)
        await model.download([row])
        await model.queue.waitUntilIdle()
        XCTAssertNotNil(try BookHelp.content(directory: cache, book: parsed.book, chapter: XCTUnwrap(parsed.chapters.first)))
        let states = await model.queue.snapshot()
        XCTAssertEqual(states.map(\.state), [.completed])
    }

    private func fixture() async throws -> (AppDatabase, BookRow, BookChapter, URL, ReplayHttpClient, DownloadCenterModel) {
        let db = try AppDatabase.inMemory()
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/tmp/review-\(UUID().uuidString)")
        var source = BookSourceRow(); source.bookSourceUrl = "https://example.invalid"
        source.ruleContent = "{\"content\":\"div@html\"}"
        try await BookSourceRepository(database: db).insert(source)
        var book = BookRow(); book.bookUrl = "https://example.invalid/book"; book.origin = source.bookSourceUrl
        book.name = "书"; book.totalChapterNum = 1
        try await BookshelfRepository(database: db).insert(book)
        var row = BookChapterRow(); row.bookUrl = book.bookUrl; row.url = "https://example.invalid/read/1"
        row.title = "章"; row.baseUrl = book.bookUrl
        try await ChapterRepository(database: db).insert(row)
        let chapter = try JSONDecoder().decode(BookChapter.self, from: JSONEncoder().encode(row))
        let client = ReplayHttpClient()
        return (db, book, chapter, directory, client, DownloadCenterModel(database: db, client: client, directory: directory))
    }

    private func imageFile(_ directory: URL, book: Book, src: String) -> URL {
        let hash = String(Insecure.MD5.hash(data: Data(src.utf8)).map { String(format: "%02x", $0) }.joined().dropFirst(8).prefix(16))
        return directory.appendingPathComponent("book_cache/\(BookHelp.folderName(book))/images/\(hash).png")
    }

    func testReview1CachedBodyRepairsMissingImagesWithoutRefetch() async throws {
        let (_, row, chapter, directory, client, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = try DiscoveryStorage.book(row)
        let src = "https://example.invalid/picture.png"
        try BookHelp.save("正文<img src=\"/picture.png\">", directory: directory, book: book, chapter: chapter)
        let url = URL(string: src)!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: png, finalURL: url))
        await model.download([row]); await model.queue.waitUntilIdle()
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.url), [url], "缺图必须下载图片，不能仅凭正文判完成")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageFile(directory, book: book, src: src).path))
        let progress = await model.queue.snapshot()
        XCTAssertEqual(progress.map(\.state), [.completed])
    }

    func testReview2EpubEmbedsImagesAndEscapesOnlyText() async throws {
        let (db, row, chapter, directory, _, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = try DiscoveryStorage.book(row), src = "https://example.invalid/picture.png"
        try BookHelp.save("正文 & <文字><img src=\"/picture.png\">结尾<img src='/picture.png'>", directory: directory, book: book, chapter: chapter)
        var rule = ReplaceRuleRow(); rule.pattern = "picture.png"; rule.replacement = "missing.png"; rule.isRegex = false
        try await ReplaceRuleRepository(database: db).insert(rule)
        let file = imageFile(directory, book: book, src: src)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: file)
        let url = try await model.export(row, range: 0...0, epub: true, useReplace: true)
        let zip = try ZipReader(url: url)
        let html = String(decoding: try XCTUnwrap(zip.readEntry("OEBPS/Text/chapter_0.html")), as: UTF8.self)
        XCTAssertTrue(html.contains("<img src=\"../Images/"), "正文图片必须是 img 元素")
        XCTAssertFalse(html.contains("&lt;img"))
        XCTAssertTrue(html.contains("正文 &amp; &lt;文字&gt;"))
        XCTAssertEqual(try zip.readEntry("OEBPS/Images/" + file.lastPathComponent), png)
        let opf = String(decoding: try XCTUnwrap(zip.readEntry("OEBPS/content.opf")), as: UTF8.self)
        XCTAssertTrue(opf.contains("href=\"Images/\(file.lastPathComponent)\" media-type=\"image/png\""))
        XCTAssertEqual(opf.components(separatedBy: "href=\"Images/\(file.lastPathComponent)\"").count, 2)
        XCTAssertEqual(html.components(separatedBy: "<img src=\"../Images/").count, 3)
    }

    func testReview1RetriesMissingImagesAndRepairsCorruptFiles() async throws {
        let (_, row, chapter, directory, client, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = try DiscoveryStorage.book(row), src = "https://example.invalid/picture.png", url = URL(string: "https://example.invalid/picture.png")!
        try BookHelp.save("<img src=\"/picture.png\">", directory: directory, book: book, chapter: chapter)
        await client.enqueue(url: url, error: URLError(.timedOut))
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: png, finalURL: url))
        await model.download([row]); await model.queue.waitUntilIdle()
        let progress = await model.queue.snapshot()
        XCTAssertEqual(progress.first?.attempts, 2)
        XCTAssertEqual(progress.first?.state, .completed)
        XCTAssertTrue(BookHelp.hasImageContent(directory: directory, book: book, chapter: chapter))
        try Data("broken".utf8).write(to: imageFile(directory, book: book, src: src))
        XCTAssertFalse(BookHelp.hasImageContent(directory: directory, book: book, chapter: chapter))
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: png, finalURL: url))
        await model.download([row]); await model.queue.waitUntilIdle()
        XCTAssertTrue(BookHelp.hasImageContent(directory: directory, book: book, chapter: chapter))
        await model.download([row]); await model.queue.waitUntilIdle()
        let requests = await client.requests
        XCTAssertEqual(requests.count, 3)
    }

    func testReview1ImageFailureNeverReportsCompleted() async throws {
        let (_, row, chapter, directory, client, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = try DiscoveryStorage.book(row), url = URL(string: "https://example.invalid/picture.png")!
        try BookHelp.save("<img src=\"/picture.png\">", directory: directory, book: book, chapter: chapter)
        for _ in 0..<3 { await client.enqueue(url: url, error: URLError(.timedOut)) }
        await model.download([row]); await model.queue.waitUntilIdle()
        let progress = await model.queue.snapshot()
        XCTAssertEqual(progress.first?.state, .failed)
        XCTAssertEqual(progress.first?.attempts, 3)
        XCTAssertTrue(BookHelp.hasContent(directory: directory, book: book, chapter: chapter))
        XCTAssertFalse(BookHelp.hasImageContent(directory: directory, book: book, chapter: chapter))
    }

    func testReview6CoverCancellationStillCancelsExport() async throws {
        let (_, original, chapter, directory, client, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var row = original; row.coverUrl = "https://example.invalid/cancelled.png"
        try BookHelp.save("正文", directory: directory, book: DiscoveryStorage.book(row), chapter: chapter)
        await client.enqueue(url: URL(string: row.coverUrl!)!, error: URLError(.cancelled))
        do {
            _ = try await model.export(row, range: 0...0, epub: true, useReplace: false)
            XCTFail("取消不能降级为成功导出")
        } catch { XCTAssertEqual((error as? URLError)?.code, .cancelled) }
        XCTAssertNil(model.errorMessage)
    }

    func testReview3OnlyUpdateReadMeansNoUnreadChapters() async throws {
        let db = try AppDatabase.inMemory()
        var group = BookGroupRow(); group.groupId = 1; group.onlyUpdateRead = true
        try await BookGroupRepository(database: db).insert(group)
        var unread = BookRow(); unread.bookUrl = "unread"; unread.name = "未读完"; unread.origin = "https://missing.invalid"
        unread.group = 1; unread.totalChapterNum = 3; unread.durChapterIndex = 0; unread.durChapterTime = 99
        var finished = unread; finished.bookUrl = "finished"; finished.name = "已读完"; finished.durChapterIndex = 2; finished.durChapterTime = 0
        try await BookshelfRepository(database: db).upsert([unread, finished])
        let report = try await BookshelfRefreshService.refresh(database: db, client: ReplayHttpClient())
        XCTAssertEqual(report.failures.map(\.bookURL), ["finished"], "已读到末章才进入刷新，不依赖阅读时间")
        let globalReport = try await BookshelfRefreshService.refresh(database: db, client: ReplayHttpClient(),
            rows: [unread, finished], onlyUpdateRead: true)
        XCTAssertEqual(globalReport.failures.map(\.bookURL), ["finished"])
    }

    func testReview6CoverFailureStillExportsAndRecordsWarning() async throws {
        let (_, original, chapter, directory, client, model) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var row = original; row.coverUrl = "https://example.invalid/failed-cover.png"
        let book = try DiscoveryStorage.book(row)
        try BookHelp.save("正文", directory: directory, book: book, chapter: chapter)
        await client.enqueue(url: URL(string: row.coverUrl!)!, error: URLError(.timedOut))
        let url = try await model.export(row, range: 0...0, epub: true, useReplace: false)
        let zip = try ZipReader(url: url)
        XCTAssertNotNil(try zip.readEntry("OEBPS/Text/chapter_0.html"))
        XCTAssertNil(try zip.readEntry("OEBPS/Images/cover.png"))
        XCTAssertNotNil(model.errorMessage, "封面失败必须留有可见错误")
    }
}

private struct StoppingRefreshClient: HttpClient {
    let started: @Sendable () -> Void
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        started()
        try await Task.sleep(for: .seconds(3600))
        throw CancellationError()
    }
}
