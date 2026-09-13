import XCTest
import LegadoCore
@testable import ReaderCheck

final class LocalBookReaderTests: XCTestCase {
    func testRefreshDoesNotReuseOldLocalBodyCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("刷新.txt")
        let db = try AppDatabase.inMemory()
        let cache = ReaderChapterCache(directory: root.appendingPathComponent("cache"))
        for content in ["旧正文", "新正文"] {
            try Data("第一章\n\(content)".utf8).write(to: url, options: .atomic)
            let parsed = try LocalBook.parse(url: url)
            try await LocalBook.save(book: parsed.book, chapters: parsed.chapters, database: db)
            let rows = try await ChapterRepository(database: db).list(bookUrl: url.absoluteString)
            let row = try XCTUnwrap(rows.first)
            let chapter = try JSONDecoder().decode(BookChapter.self, from: JSONEncoder().encode(row))
            let body = try await cache.content(book: parsed.book, chapter: chapter, nextURL: nil, source: nil, client: ReplayHttpClient())
            XCTAssertEqual(body.rawContent, "\n\(content)")
        }
    }

    func testLocalBodyLoadsWithoutSourceAndCaches() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("本地书.txt")
        try Data("第一章 开始\n本地正文".utf8).write(to: url)
        let parsed = try LocalBook.parse(url: url)
        XCTAssertNil(parsed.cover)
        let chapter = try XCTUnwrap(parsed.chapters.first)
        let cache = ReaderChapterCache(directory: root.appendingPathComponent("cache"))
        let first = try await cache.content(book: parsed.book, chapter: chapter, nextURL: nil,
                                            source: nil, client: ReplayHttpClient())
        XCTAssertEqual(first.rawContent, "\n本地正文")
        try FileManager.default.removeItem(at: url)
        let cached = try await cache.content(book: parsed.book, chapter: chapter, nextURL: nil,
                                             source: nil, client: ReplayHttpClient())
        XCTAssertEqual(cached.rawContent, first.rawContent)
    }
}
