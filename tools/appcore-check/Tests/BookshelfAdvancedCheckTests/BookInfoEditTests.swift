import XCTest
import LegadoCore
@testable import BookshelfAdvancedCheck

@MainActor
final class BookInfoEditTests: XCTestCase {
    func testMetadataSavePreservesProgressAndSourceFields() async throws {
        let db = try AppDatabase.inMemory()
        let repository = BookshelfRepository(database: db)
        var book = BookRow(); book.bookUrl = "book"; book.name = "旧名"
        book.coverUrl = "source-cover"; book.intro = "source-intro"
        try await repository.insert(book)
        let model = BookInfoEditModel(book: book, repository: repository)
        model.name = "新名"; model.author = "作者"; model.cover = "custom-cover"
        model.intro = "custom-intro"; model.tag = "标签"; model.variable = "{\"key\":\"value\"}"
        try await repository.updateProgress(bookUrl: "book", chapterIndex: 5, chapterPos: 8, chapterTitle: "第六章", readTime: 99)
        let saved = await model.save()
        XCTAssertTrue(saved)
        let result = try await repository.get(bookUrl: "book")
        XCTAssertEqual(result?.name, "新名")
        XCTAssertEqual(result?.customCoverUrl, "custom-cover")
        XCTAssertEqual(result?.coverUrl, "source-cover")
        XCTAssertEqual(result?.intro, "source-intro")
        XCTAssertEqual(result?.customIntro, "custom-intro")
        XCTAssertEqual(result?.durChapterIndex, 5)
        XCTAssertEqual(result?.variable, "{\"key\":\"value\"}")
    }

    func testInvalidCustomFieldsDoNotSave() async throws {
        let db = try AppDatabase.inMemory()
        let repository = BookshelfRepository(database: db)
        var book = BookRow(); book.bookUrl = "book"; book.name = "原名"
        try await repository.insert(book)
        let model = BookInfoEditModel(book: book, repository: repository)
        model.variable = "not-json"
        let saved = await model.save()
        XCTAssertFalse(saved)
        XCTAssertNotNil(model.errorMessage)
    }

    func testDownloadThenExportUsesCachedRawContent() async throws {
        let db = try AppDatabase.inMemory()
        let client = ReplayHttpClient()
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/tmp/b10-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var source = BookSourceRow(); source.bookSourceUrl = "https://example.invalid"
        source.ruleContent = "{\"content\":\"div@text\"}"
        try await BookSourceRepository(database: db).insert(source)
        var book = BookRow(); book.bookUrl = "https://example.invalid/book"; book.origin = source.bookSourceUrl
        book.name = "书籍"; book.totalChapterNum = 1
        try await BookshelfRepository(database: db).insert(book)
        var chapter = BookChapterRow(); chapter.bookUrl = book.bookUrl; chapter.url = "https://example.invalid/1"
        chapter.title = "第一章"; chapter.baseUrl = book.bookUrl
        try await ChapterRepository(database: db).insert(chapter)
        var rule = ReplaceRuleRow(); rule.pattern = "旧"; rule.replacement = "新"; rule.isRegex = false
        try await ReplaceRuleRepository(database: db).insert(rule)
        let url = URL(string: chapter.url)!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("<div>旧正文</div>".utf8), finalURL: url))
        let model = DownloadCenterModel(database: db, client: client, directory: directory)
        await model.download([book], range: 0...0)
        await model.queue.waitUntilIdle()
        let progress = await model.queue.snapshot()
        XCTAssertEqual(progress.map(\.state), [.completed])
        let rawURL = try await model.export(book, range: 0...0, epub: false, useReplace: false)
        XCTAssertTrue(try String(contentsOf: rawURL, encoding: .utf8).contains("旧正文"))
        let replacedURL = try await model.export(book, range: 0...0, epub: false, useReplace: true)
        XCTAssertTrue(try String(contentsOf: replacedURL, encoding: .utf8).contains("新正文"))
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testEmptyOverridesRestoreSourceFields() async throws {
        let db = try AppDatabase.inMemory()
        let repository = BookshelfRepository(database: db)
        var book = BookRow(); book.bookUrl = "book"; book.name = "名称"; book.coverUrl = "source"
        book.customCoverUrl = "custom"; book.customIntro = "custom"
        try await repository.insert(book)
        let model = BookInfoEditModel(book: book, repository: repository)
        model.cover = ""; model.intro = ""
        let saved = await model.save()
        XCTAssertTrue(saved)
        let updated = try await repository.get(bookUrl: book.bookUrl)
        XCTAssertNil(updated?.customCoverUrl)
        XCTAssertNil(updated?.customIntro)
        XCTAssertEqual(updated?.coverUrl, "source")
    }
}
