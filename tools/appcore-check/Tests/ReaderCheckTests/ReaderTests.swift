import XCTest
import CoreText
import LegadoCore
@testable import ReaderCheck

final class ReaderTests: XCTestCase {
    func testFixedFontPageBoundaryFixture() throws {
        var settings = ReaderSettings()
        settings.paddingLeft = 0; settings.paddingRight = 0
        settings.paddingTop = 0; settings.paddingBottom = 0
        settings.paragraphIndent = ""; settings.paragraphSpacing = 0
        settings.lineSpacingMultiplier = 1
        let result = try Paginator(fontName: "Menlo-Regular").paginate(title: "", paragraphs: ["abc", "def"],
            size: CGSize(width: 100, height: 30), settings: settings)
        XCTAssertEqual(result.pages.map(\.range), [NSRange(location: 0, length: 4), NSRange(location: 4, length: 3)])
        XCTAssertEqual(result.pageIndex(at: 3), 0)
        XCTAssertEqual(result.pageIndex(at: 4), 1)
    }

    func testPaginationRangesAndOffsets() throws {
        let paginator = Paginator()
        let paragraphs = Array(repeating: "固定字体分页测试。Hello 😀，下一行文字。", count: 80)
        let first = try paginator.paginate(title: "第一章", paragraphs: paragraphs,
                                           size: CGSize(width: 320, height: 480), settings: ReaderSettings())
        let second = try paginator.paginate(title: "第一章", paragraphs: paragraphs,
                                            size: CGSize(width: 320, height: 480), settings: ReaderSettings())
        XCTAssertGreaterThan(first.pages.count, 1)
        XCTAssertEqual(first.pages.map(\.range), second.pages.map(\.range))
        var offset = 0
        for (index, page) in first.pages.enumerated() {
            XCTAssertEqual(page.range.location, offset)
            XCTAssertGreaterThan(page.range.length, 0)
            XCTAssertEqual(first.pageIndex(at: offset), index)
            XCTAssertEqual(first.firstCharacterOffset(on: index), offset)
            XCTAssertEqual(page.text.string, (first.text.string as NSString).substring(with: page.range))
            let frameRange = CTFrameGetVisibleStringRange(try XCTUnwrap(page.frame))
            XCTAssertEqual(frameRange.location, page.range.location)
            XCTAssertEqual(frameRange.length, page.range.length)
            offset = NSMaxRange(page.range)
        }
        XCTAssertEqual(offset, first.text.length)
        XCTAssertEqual(first.pageIndex(at: -100), 0)
        XCTAssertEqual(first.pageIndex(at: Int.max), first.pages.count - 1)
        XCTAssertThrowsError(try paginator.paginate(title: "章", paragraphs: ["正文"], size: .zero, settings: .init()))
    }

    @MainActor
    func testFetchReplaceTurnPersistAndCache() async throws {
        let database = try AppDatabase.inMemory()
        let client = ReplayHttpClient()
        var book = BookRow(); book.bookUrl = "https://reader.test/book"; book.origin = "https://reader.test"; book.name = "测试书"
        try await BookshelfRepository(database: database).insert(book)
        var source = BookSourceRow(); source.bookSourceUrl = book.origin; source.ruleContent = #"{"content":"tag.p@text"}"#
        try await BookSourceRepository(database: database).insert(source)
        for index in 0...1 {
            var chapter = BookChapterRow(); chapter.bookUrl = book.bookUrl; chapter.index = index
            chapter.url = "https://reader.test/\(index)"; chapter.title = "第\(index)章"
            try await ChapterRepository(database: database).insert(chapter)
            let url = URL(string: chapter.url)!
            await client.enqueue(url: url, response: HttpResponse(status: 200,
                body: Data("<p>旧字正文</p>".utf8), finalURL: url))
        }
        var rule = ReplaceRuleRow(); rule.pattern = "旧字"; rule.replacement = "新字"; rule.isRegex = false
        rule = try await ReplaceRuleRepository(database: database).insert(rule)
        var bookmark = BookmarkRow(); bookmark.time = 42; bookmark.bookName = book.name
        bookmark.bookAuthor = book.author; bookmark.chapterIndex = 1; bookmark.chapterPos = 12
        try await BookmarkRepository(database: database).insert(bookmark)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ReaderViewModel(database: database, client: client, cacheDirectory: directory, now: { 1234 })
        await model.load(bookURL: book.bookUrl, chapterIndex: 0)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.bookmarks.map(\.time), [42])
        XCTAssertTrue(model.pagination?.text.string.contains("新字正文") == true)
        await model.waitForPrefetch()
        await model.nextPage()
        XCTAssertEqual(model.chapterIndex, 1)
        let saved = try await BookshelfRepository(database: database).get(bookUrl: book.bookUrl)
        XCTAssertEqual(saved?.durChapterIndex, 1)
        XCTAssertEqual(saved?.durChapterPos, 0)
        XCTAssertEqual(saved?.durChapterTitle, "第1章")
        XCTAssertEqual(saved?.durChapterTime, 1234)
        rule.replacement = "更新字"
        try await ReplaceRuleRepository(database: database).update(rule)
        await model.previousChapter()
        XCTAssertEqual(model.chapterIndex, 0)
        XCTAssertTrue(model.pagination?.text.string.contains("更新字正文") == true)
        await model.waitForPrefetch()
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
        let restored = ReaderViewModel(database: database, client: client, cacheDirectory: directory, now: { 1234 })
        await restored.load(bookURL: book.bookUrl)
        XCTAssertNil(restored.errorMessage)
        await restored.waitForPrefetch()
        let cachedRequests = await client.requests
        XCTAssertEqual(cachedRequests.count, 2)
        await restored.close()
        await model.close()
    }

    @MainActor
    func testSavedOffsetReflowAndFailedChapter() async throws {
        let database = try AppDatabase.inMemory()
        let client = ReplayHttpClient()
        var book = BookRow(); book.bookUrl = "https://reader.test/long"; book.origin = "https://reader.test"
        try await BookshelfRepository(database: database).insert(book)
        var source = BookSourceRow(); source.bookSourceUrl = book.origin; source.ruleContent = #"{"content":"tag.p@text"}"#
        try await BookSourceRepository(database: database).insert(source)
        for index in 0...1 {
            var chapter = BookChapterRow(); chapter.bookUrl = book.bookUrl; chapter.index = index
            chapter.url = "https://reader.test/long/\(index)"; chapter.title = "第\(index)章"
            try await ChapterRepository(database: database).insert(chapter)
        }
        let url = URL(string: "https://reader.test/long/0")!
        let text = String(repeating: "<p>章节分页正文，包含😀和连续文字，验证偏移恢复。</p>", count: 100)
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data(text.utf8), finalURL: url))
        let failedURL = URL(string: "https://reader.test/long/1")!
        await client.enqueue(url: failedURL, error: URLError(.notConnectedToInternet))
        await client.enqueue(url: failedURL, error: URLError(.notConnectedToInternet))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ReaderViewModel(database: database, client: client, cacheDirectory: directory, now: { 5678 })
        await model.load(bookURL: book.bookUrl)
        await model.waitForPrefetch()
        XCTAssertNotNil(model.prefetchErrorMessage)
        await model.selectPage(2)
        let anchor = model.characterOffset
        XCTAssertGreaterThan(anchor, 0)
        let restored = ReaderViewModel(database: database, client: client, cacheDirectory: directory, now: { 5678 })
        await restored.load(bookURL: book.bookUrl)
        XCTAssertEqual(restored.characterOffset, anchor)
        await restored.waitForPrefetch()
        await restored.close()
        var settings = ReaderSettings(); settings.textSize = 24
        await model.reflow(settings: settings)
        let page = try XCTUnwrap(model.pagination?.pages[model.pageIndex])
        XCTAssertTrue(NSLocationInRange(anchor, page.range))
        let offset = model.characterOffset
        await client.enqueue(url: failedURL, error: URLError(.notConnectedToInternet))
        await model.nextChapter()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.chapterIndex, 0)
        XCTAssertEqual(model.characterOffset, offset)
        await model.close()
        let saved = try await BookshelfRepository(database: database).get(bookUrl: book.bookUrl)
        XCTAssertEqual(saved?.durChapterPos, offset)
        XCTAssertEqual(saved?.durChapterIndex, 0)
        XCTAssertEqual(saved?.durChapterTime, 5678)
    }

    func testSettingsPersistence() {
        let name = "ReaderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = ReaderSettings.load(from: defaults)
        XCTAssertEqual(settings.textSize, 20)
        XCTAssertEqual(settings.lineSpacingMultiplier, 1.2)
        settings.textSize = 26; settings.theme = .night; settings.lineSpacingMultiplier = 1.5
        settings.save(to: defaults)
        XCTAssertEqual(defaults.integer(forKey: "lineSpacingExtra"), 15)
        XCTAssertEqual(ReaderSettings.load(from: defaults), settings)
        defaults.set(-500, forKey: "textSize")
        defaults.set(0, forKey: "lineSpacingExtra")
        let normalized = ReaderSettings.load(from: defaults)
        XCTAssertEqual(normalized.textSize, 12)
        XCTAssertEqual(normalized.lineSpacingMultiplier, 1)
    }
}
