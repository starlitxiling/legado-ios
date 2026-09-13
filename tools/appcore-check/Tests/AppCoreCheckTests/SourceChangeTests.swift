import XCTest
import LegadoCore
@testable import AppCoreCheck

@MainActor
final class SourceChangeTests: XCTestCase {
    private let fixtures = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/Conformance/fixtures/webbook")

    private func source() throws -> BookSource {
        try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: fixtures.appendingPathComponent("source.json")))
    }

    private func enqueue(_ client: ReplayHttpClient, path: String, file: String) async throws {
        let url = URL(string: "https://example.invalid" + path)!
        await client.enqueue(url: url, response: HttpResponse(status: 200,
            body: try Data(contentsOf: fixtures.appendingPathComponent(file)), finalURL: url))
    }

    func testUncachedSourceMigratesProgressBeforeAndAfterSaving() async throws {
        let db = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: db)
        let sources = BookSourceRepository(database: db)
        try await sources.insert(DiscoveryStorage.row(source(), defaults: BookSourceRow()))
        var old = BookRow()
        old.bookUrl = "https://old.invalid/1"; old.name = "航海记"; old.author = "林舟"
        old.durChapterIndex = 7; old.durChapterPos = 25; old.durChapterTitle = "旧章节"; old.durChapterTime = 123
        old.totalChapterNum = 40
        try await shelf.insert(old)
        var result = SearchBook(now: 0)
        result.bookUrl = "https://example.invalid/book/1"; result.origin = "https://example.invalid"
        result.name = old.name; result.author = old.author
        let client = ReplayHttpClient()
        try await enqueue(client, path: "/book/1", file: "info.html")
        let model = BookDetailViewModel(results: [result], sources: sources, bookshelf: shelf, client: client)
        await model.load()
        XCTAssertEqual(model.book?.bookUrl, result.bookUrl)
        XCTAssertEqual(model.book?.durChapterIndex, 7)
        XCTAssertEqual(model.book?.durChapterPos, 25)
        XCTAssertEqual(model.book?.durChapterTitle, "旧章节")
        XCTAssertEqual(model.book?.durChapterTime, 123)
        old.durChapterIndex = 8; old.durChapterPos = 30; old.durChapterTitle = "新进度"; old.durChapterTime = 456
        try await shelf.upsert(old)
        await model.toggleBookshelf()
        XCTAssertNil(model.errorMessage)
        let saved = try await shelf.get(bookUrl: result.bookUrl!)
        XCTAssertEqual(model.book?.durChapterIndex, saved?.durChapterIndex)
        XCTAssertEqual(model.book?.durChapterPos, saved?.durChapterPos)
        XCTAssertEqual(model.book?.durChapterTitle, saved?.durChapterTitle)
        XCTAssertEqual(model.book?.durChapterTime, saved?.durChapterTime)
    }

    func testMigrationMatchesKotlinMigrateToFields() {
        var old = BookRow()
        old.canUpdate = false; old.group = 4; old.order = 9
        old.customCoverUrl = "custom"; old.persistedCoverUrl = "persisted"
        old.customIntro = "简介"; old.customTag = "标签"; old.readConfig = "{}"
        old.variable = "旧源变量"; old.type = 32
        var incoming = BookRow(); incoming.variable = "新源变量"; incoming.type = 8
        let migrated = DiscoveryStorage.preservingReading(old, in: incoming)
        XCTAssertFalse(migrated.canUpdate)
        XCTAssertEqual(migrated.persistedCoverUrl, "persisted")
        XCTAssertEqual(migrated.group, 4); XCTAssertEqual(migrated.order, 9)
        XCTAssertEqual(migrated.customCoverUrl, "custom"); XCTAssertEqual(migrated.customIntro, "简介")
        XCTAssertEqual(migrated.customTag, "标签"); XCTAssertEqual(migrated.readConfig, "{}")
        XCTAssertEqual(migrated.variable, "新源变量")
        XCTAssertEqual(migrated.type, 8)
    }

    func testChapterLocatorUsesRatioNearestTitleAndNumberFallback() {
        var titles = (0..<200).map { "第\($0 + 1)章 其他\($0)" }
        titles[80] = "第81章 凶鹿（一）"
        titles[100] = "第101章 凶鹿（二）"
        XCTAssertEqual(ChapterLocator.locate(oldIndex: 50, oldTitle: "第５１章 凶鹿（三）",
            oldCount: 100, titles: titles), 100)
        XCTAssertEqual(ChapterLocator.locate(oldIndex: 7, oldTitle: "第壹佰贰拾章 原名",
            oldCount: 100, titles: ["第119章 新名", "第１２０回 新名"]), 1)
        XCTAssertEqual(ChapterLocator.locate(oldIndex: 99, oldTitle: nil, oldCount: 0, titles: ["甲", "乙"]), 1)
        XCTAssertEqual(ChapterLocator.locate(oldIndex: 7, oldTitle: nil, oldCount: 10, titles: []), 7)
        XCTAssertEqual(ChapterLocator.locate(oldIndex: 0, oldTitle: "乙", oldCount: 2, titles: ["甲", "乙"]), 0)
    }

    func testTocMatchesOldTitleAndClampsOutOfRangeIndex() async throws {
        for (index, title, expected) in [(7, "第一章 启航", 0), (99, "无匹配标题", 1)] {
            let db = try AppDatabase.inMemory()
            let shelf = BookshelfRepository(database: db)
            var old = BookRow()
            old.bookUrl = "https://old.invalid/1"; old.name = "航海记"; old.author = "林舟"
            old.durChapterIndex = index; old.durChapterTitle = title; old.totalChapterNum = 100
            old.durChapterPos = 15; old.durChapterTime = 123
            try await shelf.insert(old)
            var book = try DiscoveryStorage.book(old)
            book.bookUrl = "https://example.invalid/book/1"; book.tocUrl = "https://example.invalid/toc/1"
            let client = ReplayHttpClient()
            try await enqueue(client, path: "/toc/1", file: "toc1.html")
            try await enqueue(client, path: "/toc/2", file: "toc2.html")
            let model = TocViewModel(book: book, source: try source(), chapters: ChapterRepository(database: db),
                                     bookshelf: shelf, client: client, database: db)
            await model.refresh()
            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(model.book.durChapterIndex, expected)
            XCTAssertEqual(model.book.durChapterTitle, expected == 0 ? "启航" : "归来")
            XCTAssertEqual(model.currentChapterIndex, expected)
            let saved = try await shelf.get(bookUrl: book.bookUrl!)
            XCTAssertEqual(saved?.durChapterIndex, expected)
            XCTAssertEqual(saved?.durChapterPos, 15)
            XCTAssertEqual(saved?.durChapterTime, 123)
        }
    }

    func testFailedSourceChangeRollsBackBookChaptersAndProgress() async throws {
        let db = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: db)
        let chapters = ChapterRepository(database: db)
        var old = BookRow()
        old.bookUrl = "https://old.invalid/1"; old.name = "航海记"; old.author = "林舟"
        old.durChapterIndex = 3; old.durChapterPos = 25
        try await shelf.insert(old)
        var chapter = BookChapterRow()
        chapter.bookUrl = old.bookUrl; chapter.url = "old-chapter"; chapter.title = "旧目录"
        try await chapters.insert(chapter)
        try await db.write { database in
            try database.execute(sql: """
                CREATE TRIGGER reject_new_chapters BEFORE INSERT ON chapters
                WHEN NEW.bookUrl = 'https://example.invalid/book/1'
                BEGIN SELECT RAISE(ABORT, 'injected chapter failure'); END
                """)
        }
        var book = try DiscoveryStorage.book(old)
        book.bookUrl = "https://example.invalid/book/1"; book.tocUrl = "https://example.invalid/toc/1"
        let client = ReplayHttpClient()
        try await enqueue(client, path: "/toc/1", file: "toc1.html")
        try await enqueue(client, path: "/toc/2", file: "toc2.html")
        let model = TocViewModel(book: book, source: try source(), chapters: chapters, bookshelf: shelf, client: client, database: db)
        await model.refresh()
        XCTAssertTrue(model.errorMessage?.contains("injected chapter failure") == true)
        let storedBooks = try await shelf.all()
        let storedChapters = try await chapters.all()
        XCTAssertEqual(storedBooks, [old])
        XCTAssertEqual(storedChapters, [chapter])
        XCTAssertEqual(model.book, book)
    }
}
