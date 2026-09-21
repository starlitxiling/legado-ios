import XCTest
import LegadoCore
@testable import LocalImportCheck

@MainActor
final class LocalImportTests: XCTestCase {
    func testStorageFolderStaysInsideDocuments() throws {
        let documents = FileManager.default.temporaryDirectory.appendingPathComponent("library-root")
        XCTAssertEqual(try LocalImportViewModel.storageDirectory(folder: " Custom ", documents: documents), documents.appendingPathComponent("Custom", isDirectory: true))
        for invalid in ["", ".", "..", "../outside", "nested/folder", "a\\b"] {
            XCTAssertThrowsError(try LocalImportViewModel.storageDirectory(folder: invalid, documents: documents))
        }
    }

    func testArchiveImportsEveryBookAndKeepsStableURLsAndProgress() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/localbook/two-books.zip")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try AppDatabase.inMemory()
        let model = LocalImportViewModel(database: db, booksDirectory: root)
        await model.importFiles([fixture])
        XCTAssertTrue(model.errors.isEmpty, model.errors.joined())
        XCTAssertEqual(model.importedCount, 2)
        let books = try await BookshelfRepository(database: db).list()
        let first = try XCTUnwrap(books.first)
        try await BookshelfRepository(database: db).updateProgress(bookUrl: first.bookUrl, chapterIndex: 0,
            chapterPos: 3, chapterTitle: "Page", readTime: 123)
        await model.importFiles([fixture])
        XCTAssertTrue(model.errors.isEmpty, model.errors.joined())
        let repeated = try await BookshelfRepository(database: db).list()
        XCTAssertEqual(Set(repeated.map(\.bookUrl)), Set(books.map(\.bookUrl)))
        XCTAssertEqual(repeated.first { $0.bookUrl == first.bookUrl }?.durChapterPos, 3)
        for row in repeated {
            let book = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(row))
            let chapter = try XCTUnwrap(LocalBook.chapterList(book: book).last)
            XCTAssertTrue(try LocalBook.content(book: book, chapter: chapter).contains("final page"))
        }
    }

    func testArchiveKeepCopyOnlyRetriesConflictingMembers() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/localbook/two-books.zip")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try AppDatabase.inMemory()
        var existing = BookRow(); existing.bookUrl = "fixture:existing"; existing.name = "First"; existing.author = ""
        try await BookshelfRepository(database: db).insert(existing)
        let model = LocalImportViewModel(database: db, booksDirectory: root)
        await model.importFiles([fixture])
        XCTAssertEqual(model.importedCount, 1)
        XCTAssertEqual(model.conflictingURLs, [fixture])
        await model.confirmKeepCopy(fixture)
        XCTAssertTrue(model.errors.isEmpty, model.errors.joined())
        XCTAssertEqual(model.importedCount, 1)
        let books = try await BookshelfRepository(database: db).list()
        XCTAssertEqual(Set(books.map(\.name)), ["First", "First (2)", "Second"])
    }

    func testImportPersistsBookAndChapters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("书名 by 作者.txt")
        try Data(("第一章 开始\n" + String(repeating: "这是正文。", count: 250) + "\n第二章 结束\n完结").utf8).write(to: input)
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
