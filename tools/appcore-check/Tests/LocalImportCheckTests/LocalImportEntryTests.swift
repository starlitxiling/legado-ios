import XCTest
import LegadoCore
@testable import LocalImportCheck

@MainActor
final class LocalImportEntryTests: XCTestCase {
    func testDirectoryBookmarkSurvivesReloadAndScanningSkipsLinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("Body".utf8).write(to: nested.appendingPathComponent("Book.txt"))
        try Data().write(to: root.appendingPathComponent("image.png"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.txt"), withDestinationURL: nested.appendingPathComponent("Book.txt"))
        let suite = "LocalScan." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scanner = LocalDirectoryScanner(defaults: defaults)
        await scanner.add(root)
        XCTAssertNil(scanner.errorMessage)
        XCTAssertEqual(scanner.files.map(\.lastPathComponent), ["Book.txt"])
        let restored = LocalDirectoryScanner(defaults: defaults)
        let id = try XCTUnwrap(restored.directories.first?.id)
        await restored.scan(id)
        XCTAssertNil(restored.errorMessage)
        XCTAssertEqual(restored.files.map(\.lastPathComponent), ["Book.txt"])
        XCTAssertThrowsError(try LocalDirectoryScanner.enumerate(root, maximumEntries: 1))
        let db = try AppDatabase.inMemory()
        let model = LocalImportViewModel(database: db, booksDirectory: root.appendingPathComponent("Imported"))
        await restored.importScanned(using: model)
        XCTAssertTrue(model.errors.isEmpty, model.errors.joined())
        XCTAssertEqual(model.importedCount, 1)
        restored.remove(id)
        XCTAssertTrue(LocalDirectoryScanner(defaults: defaults).directories.isEmpty)
    }

    func testOnlineFileDownloadImportAndErrors() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try AppDatabase.inMemory(), client = ReplayHttpClient()
        let model = LocalImportViewModel(database: db, booksDirectory: root)
        let url = URL(string: "https://fixture.test/download?id=1")!
        await client.enqueue(url: url, response: .init(status: 200, body: Data("Final page".utf8), finalURL: url,
            headers: ["Content-Disposition": "attachment; filename*=UTF-8''Book.txt"]))
        await model.importOnline(url.absoluteString, client: client)
        XCTAssertEqual(model.importedCount, 1)
        XCTAssertTrue(model.errors.isEmpty, model.errors.joined())
        XCTAssertFalse(model.isDownloading)
        let books = try await BookshelfRepository(database: db).all()
        XCTAssertEqual(books.first?.name, "Book")
        await client.enqueue(url: url, response: .init(status: 403, finalURL: url))
        await model.importOnline(url.absoluteString, client: client)
        XCTAssertEqual(model.errors.count, 1)
        XCTAssertTrue(model.errors[0].contains("403"))
        await model.importOnline(root.appendingPathComponent("private.txt").absoluteString, client: client)
        XCTAssertEqual(model.errors.count, 1)
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.method), ["GET", "GET"])
    }
    func testFilenameScriptFlowsThroughImportAndFallsBackOnError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("Writer - Title.txt")
        try Data("Body".utf8).write(to: input)
        let db = try AppDatabase.inMemory()
        var script = "var p = src.split(' - '); var name = p[1]; var author = p[0];"
        let model = LocalImportViewModel(database: db, booksDirectory: root.appendingPathComponent("Books"), filenameScript: { script })
        await model.importFiles([input])
        XCTAssertTrue(model.errors.isEmpty, model.errors.joined())
        var books = try await BookshelfRepository(database: db).list()
        XCTAssertEqual(books.first?.name, "Title")
        XCTAssertEqual(books.first?.author, "Writer")
        script = "throw new Error('filename failure')"
        await model.importFiles([input])
        XCTAssertTrue(model.errors.isEmpty, model.errors.joined())
        books = try await BookshelfRepository(database: db).list()
        XCTAssertEqual(books.first?.name, "Writer - Title")
        XCTAssertTrue(AppLogStore.shared.snapshot().contains { $0.message.contains("filename failure") })
    }

    func testEpubCoverUsesBookHashAndFailedImportDoesNotLeakCover() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/localbook/nested-nav.epub")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try AppDatabase.inMemory()
        let model = LocalImportViewModel(database: db, booksDirectory: root)
        await model.importFiles([fixture])
        XCTAssertTrue(model.errors.isEmpty, model.errors.joined())
        let books = try await BookshelfRepository(database: db).list()
        let book = try XCTUnwrap(books.first)
        let cover = LocalBook.coverURL(bookURL: book.bookUrl, root: root)
        XCTAssertEqual(book.coverUrl, cover.absoluteString)
        let original = try Data(contentsOf: cover)
        XCTAssertFalse(original.isEmpty)
        let copy = root.appendingPathComponent("copy.epub")
        try FileManager.default.copyItem(at: fixture, to: copy)
        await model.importFiles([copy])
        XCTAssertFalse(model.errors.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: cover.deletingLastPathComponent(), includingPropertiesForKeys: nil).map { $0.resolvingSymlinksInPath() }, [cover.resolvingSymlinksInPath()])
        XCTAssertEqual(try Data(contentsOf: cover), original)
    }

}
