import XCTest
import CryptoKit
import LegadoCore
@testable import BookshelfAdvancedCheck

@MainActor
final class BookshelfReviewTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!

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
