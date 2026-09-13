import XCTest
import LegadoCore
@testable import LocalImportCheck

@MainActor
final class LocalImportTests: XCTestCase {
    func testImportPersistsBookAndChapters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("书名 by 作者.txt")
        try Data("第一章 开始\n这是正文\n第二章 结束\n完结".utf8).write(to: input)
        let database = try AppDatabase.inMemory()
        let model = LocalImportViewModel(database: database, booksDirectory: root.appendingPathComponent("Books"))
        await model.importFiles([input])
        XCTAssertTrue(model.errors.isEmpty, model.errors.joined(separator: "\n"))
        XCTAssertEqual(model.importedCount, 1)
        let books = try await BookshelfRepository(database: database).list()
        XCTAssertEqual(books.count, 1)
        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(book.name, "书名")
        XCTAssertEqual(book.author, "作者")
        XCTAssertNotEqual(book.bookUrl, input.absoluteString)
        let chapters = try await ChapterRepository(database: database).list(bookUrl: book.bookUrl)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(string: book.bookUrl)!.path))
    }

    func testRepeatImportUsesStableURLAndPreservesProgress() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("复用.txt")
        try Data("第一章 标题\n正文".utf8).write(to: input)
        let db = try AppDatabase.inMemory()
        let model = LocalImportViewModel(database: db, booksDirectory: root.appendingPathComponent("Books"))
        await model.importFiles([input])
        let books = try await BookshelfRepository(database: db).list()
        let book = try XCTUnwrap(books.first)
        try await BookshelfRepository(database: db).updateProgress(bookUrl: book.bookUrl, chapterIndex: 0,
            chapterPos: 3, chapterTitle: "标题", readTime: 123)
        await model.importFiles([input])
        XCTAssertTrue(model.errors.isEmpty, model.errors.joined())
        XCTAssertEqual(model.importedCount, 1)
        let refreshed = try await BookshelfRepository(database: db).list()
        XCTAssertEqual(refreshed.count, 1)
        XCTAssertEqual(refreshed.first?.bookUrl, book.bookUrl)
        XCTAssertEqual(refreshed.first?.durChapterPos, 3)
    }

    func testConflictRequiresConfirmationAndKeepsBothBooks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("冲突 by 作者.txt")
        try Data("第一章\n正文".utf8).write(to: input)
        let db = try AppDatabase.inMemory()
        var network = BookRow(); network.bookUrl = "https://example.invalid/book"
        network.name = "冲突"; network.author = "作者"; network.durChapterPos = 12
        try await BookshelfRepository(database: db).insert(network)
        let model = LocalImportViewModel(database: db, booksDirectory: root.appendingPathComponent("Books"))
        await model.importFiles([input])
        XCTAssertEqual(model.conflictingURLs, [input]); XCTAssertEqual(model.importedCount, 0)
        await model.confirmKeepCopy(input)
        XCTAssertTrue(model.errors.isEmpty, model.errors.joined())
        let books = try await BookshelfRepository(database: db).list()
        XCTAssertEqual(Set(books.map(\.name)), ["冲突", "冲突 (2)"])
        XCTAssertEqual(books.first { $0.bookUrl == network.bookUrl }?.durChapterPos, 12)
        await model.confirmKeepCopy(input)
        let copied = try await BookshelfRepository(database: db).list()
        XCTAssertTrue(copied.contains { $0.name == "冲突 (3)" })
        XCTAssertTrue(model.conflictingURLs.isEmpty)
    }

    func testInvalidRegexAndFailedImport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try AppDatabase.inMemory()
        let model = LocalImportViewModel(database: database, booksDirectory: root)
        await model.importFiles([root.appendingPathComponent("missing.txt")])
        XCTAssertEqual(model.importedCount, 0)
        XCTAssertEqual(model.errors.count, 1)
        await model.loadRules()
        var rule = try XCTUnwrap(model.rules.first)
        rule.rule = "["
        await model.saveRule(rule)
        XCTAssertNotNil(model.ruleError)
    }
}
