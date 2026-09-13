import XCTest
import LegadoCore
@testable import LocalImportCheck

@MainActor
final class MobiImportTests: XCTestCase {
    func testMobiAndPDFImportPersistsChaptersAndText() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/tmp/b7-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for ext in ["mobi", "azw3", "pdf"] {
            let db = try AppDatabase.inMemory()
            let input = root.appendingPathComponent("sample." + ext)
            let data = try ext == "pdf" ? MobiPdfTests.pdf() : MobiPdfTests.mobi()
            try data.write(to: input)
            let model = LocalImportViewModel(database: db, booksDirectory: root.appendingPathComponent("Books"))
            await model.importFiles([input])
            XCTAssertTrue(model.errors.isEmpty, model.errors.joined())
            XCTAssertEqual(model.importedCount, 1)
            let books = try await BookshelfRepository(database: db).list()
            let row = try XCTUnwrap(books.first)
            XCTAssertEqual(row.name, ext == "pdf" ? "sample" : "合成书名")
            let chapters = try await ChapterRepository(database: db).list(bookUrl: row.bookUrl)
            XCTAssertEqual(chapters.count, ext == "pdf" ? 1 : 2)
            let book = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(row))
            let chapter = try JSONDecoder().decode(BookChapter.self, from: JSONEncoder().encode(XCTUnwrap(chapters.first)))
            XCTAssertTrue(try LocalBook.content(book: book, chapter: chapter).contains(ext == "pdf" ? "First page text" : "Alpha Alpha"))
        }
    }
    func testImportRejectsMalformedMobiAtParserInsteadOfExtensionGate() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/tmp/b7-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try AppDatabase.inMemory()
        for ext in ["mobi", "azw3", "pdf"] {
            let input = root.appendingPathComponent("invalid." + ext)
            try Data("invalid".utf8).write(to: input)
            let model = LocalImportViewModel(database: db, booksDirectory: root.appendingPathComponent("Books"))
            await model.importFiles([input])
            XCTAssertEqual(model.importedCount, 0)
            XCTAssertEqual(model.errors.count, 1)
            XCTAssertFalse(model.errors.joined().contains(LocalBookError.unsupportedFile.localizedDescription))
        }
        let books = try await BookshelfRepository(database: db).list()
        XCTAssertTrue(books.isEmpty)
    }
}
