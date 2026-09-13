import XCTest
@testable import LegadoCore

final class BookshelfReviewTests: XCTestCase {
    private func chapter(_ index: Int, title: String, url: String) -> BookChapterRow {
        var row = BookChapterRow(); row.bookUrl = "book"; row.index = index; row.title = title; row.url = url
        return row
    }

    func testReview4RelocatesByTitleThenURLAndClamps() async throws {
        for mode in ["title", "url", "clamp"] {
            let db = try AppDatabase.inMemory()
            let books = BookshelfRepository(database: db)
            var book = BookRow(); book.bookUrl = "book"; book.name = "书"; book.totalChapterNum = 3
            book.durChapterIndex = mode == "clamp" ? 7 : 1; book.durChapterTitle = "正在读"; book.durChapterPos = 12
            try await books.insert(book)
            try await ChapterRepository(database: db).insert(chapter(book.durChapterIndex, title: "正在读", url: "stable"))
            let incoming = mode == "clamp" ? [chapter(0, title: "唯一章", url: "only")]
                : [chapter(0, title: "插入章", url: "new0"), chapter(1, title: "前一章", url: "new1"),
                   chapter(2, title: mode == "title" ? "正在读" : "改名章", url: mode == "title" ? "new2" : "stable")]
            try await books.saveChapterUpdate(bookURL: "book", chapters: incoming, checkedAt: 100)
            let saved = try await books.get(bookUrl: "book")
            XCTAssertEqual(saved?.durChapterIndex, mode == "clamp" ? 0 : 2, mode)
            XCTAssertEqual(saved?.durChapterTitle, incoming.last?.title, mode)
            XCTAssertEqual(saved?.durChapterPos, 12)
        }
    }

    func testReview5UnchangedOrShrunkTOCPreservesUpdateCount() async throws {
        for count in [2, 1, 3] {
            let db = try AppDatabase.inMemory(), timestamp: Int64 = 100
            let books = BookshelfRepository(database: db)
            var book = BookRow(); book.bookUrl = "book"; book.totalChapterNum = 2; book.lastCheckCount = 7; book.latestChapterTime = 33
            try await books.insert(book)
            let incoming = (0..<count).map { chapter($0, title: "章\($0)", url: "url\($0)") }
            try await books.saveChapterUpdate(bookURL: "book", chapters: incoming, checkedAt: timestamp)
            let saved = try await books.get(bookUrl: "book")
            XCTAssertEqual(saved?.lastCheckCount, count > 2 ? 1 : 7)
            XCTAssertEqual(saved?.latestChapterTime, count > 2 ? timestamp : 33)
            XCTAssertEqual(saved?.lastCheckTime, timestamp)
        }
    }

    func testReview4UsesKotlinNormalizedTitlesAndKeepsFirstChapter() async throws {
        for oldIndex in [0, 1] {
            let db = try AppDatabase.inMemory()
            let repository = BookshelfRepository(database: db)
            var book = BookRow(); book.bookUrl = "book"; book.totalChapterNum = 3
            book.durChapterIndex = oldIndex; book.durChapterTitle = "第十章：在风中"
            try await repository.insert(book)
            let incoming = [chapter(0, title: "第一章", url: "a"), chapter(1, title: "第二章", url: "b"),
                            chapter(2, title: "第10章 在风中", url: "c")]
            try await repository.saveChapterUpdate(bookURL: "book", chapters: incoming, checkedAt: 100)
            let saved = try await repository.get(bookUrl: "book")
            XCTAssertEqual(saved?.durChapterIndex, oldIndex == 0 ? 0 : 2)
        }
    }
}
