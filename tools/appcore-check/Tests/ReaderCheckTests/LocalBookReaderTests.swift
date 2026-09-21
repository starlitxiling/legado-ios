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
            XCTAssertEqual(body.rawContent, "第一章\n\(content)")
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
        XCTAssertEqual(first.rawContent, "第一章 开始\n本地正文")
        try FileManager.default.removeItem(at: url)
        let cached = try await cache.content(book: parsed.book, chapter: chapter, nextURL: nil,
                                             source: nil, client: ReplayHttpClient())
        XCTAssertEqual(cached.rawContent, first.rawContent)
    }
    @MainActor
    func testReaderRebuildsChangedFileAndUsesNewCacheRevision() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("book.txt")
        try Data("Old content".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: url.path)
        let db = try AppDatabase.inMemory()
        let parsed = try LocalBook.parse(url: url)
        try await LocalBook.save(book: parsed.book, chapters: parsed.chapters, database: db)
        let model = ReaderViewModel(database: db, client: ReplayHttpClient(), cacheDirectory: root.appendingPathComponent("cache"), preDownloadCount: { 0 })
        await model.load(bookURL: url.absoluteString)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.pagination?.text.string.contains("Old content") == true)
        for (index, text) in ["New content", "Latest content"].enumerated() {
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(2000 + index))], ofItemAtPath: url.path)
            await model.load(bookURL: url.absoluteString)
            XCTAssertNil(model.errorMessage)
            XCTAssertTrue(model.pagination?.text.string.contains(text) == true)
            let chapters = try await ChapterRepository(database: db).list(bookUrl: url.absoluteString)
            XCTAssertEqual(model.chapters.first?.variable, chapters.first?.variable)
        }
    }

}
