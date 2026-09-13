import XCTest
import LegadoCore
@testable import ReaderCheck

final class ReaderWebDavTests: XCTestCase {
    @MainActor
    func testRestoredLocalBindingAndReaderSyncEventsPreserveIdentity() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/reader-webdav-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("book.txt")
        try Data("第一章 开始\n正文。\n第二章 后续\n下章正文。".utf8).write(to: file)
        let parsed = try LocalBook.parse(url: file)
        let database = try AppDatabase.inMemory()
        let original = try await LocalBook.save(book: parsed.book, chapters: parsed.chapters, database: database)
        let relocated = root.appendingPathComponent("relocated.txt")
        try FileManager.default.moveItem(at: file, to: relocated)
        var bound = original
        bound.variable = String(decoding: try JSONEncoder().encode(["legadoIOSLocalFile": relocated.absoluteString]), as: UTF8.self)
        let model = ReaderViewModel(database: database, client: ReplayHttpClient(), cacheDirectory: root.appendingPathComponent("cache"), preDownloadCount: { 0 }, now: { 1234 })
        var prepared = 0
        model.prepareLocalBook = { _ in prepared += 1; return bound }
        var events: [Bool] = []
        model.synchronizeWebDav = { book, exiting in
            events.append(exiting)
            var remote = BookProgress(book: book); remote.durChapterIndex = 1
            return remote
        }
        await model.load(bookURL: original.bookUrl)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(prepared, 1)
        XCTAssertEqual(model.book?.bookUrl, original.bookUrl)
        let saved = try await BookshelfRepository(database: database).get(bookUrl: original.bookUrl)
        XCTAssertEqual(saved?.variable, bound.variable)
        await model.syncWebDavProgress()
        let pending = try XCTUnwrap(model.pendingWebDavProgress)
        model.pendingWebDavProgress = nil
        await model.acceptWebDavProgress(pending)
        XCTAssertEqual(model.chapterIndex, 1)
        await model.close()
        await model.close()
        await model.syncWebDavProgress()
        XCTAssertEqual(events, [false, true])
    }
}

extension ReaderWebDavTests {
    @MainActor
    func testMissingChaptersAreRebuiltFromRestoredFile() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/reader-rebuild-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("book.txt")
        try Data("没有章节标题的正文。".utf8).write(to: file)
        let parsed = try LocalBook.parse(url: file)
        let database = try AppDatabase.inMemory()
        let original = try await LocalBook.save(book: parsed.book, chapters: [], database: database)
        let relocated = root.appendingPathComponent("restored.txt")
        try FileManager.default.moveItem(at: file, to: relocated)
        var restored = original
        restored.variable = String(decoding: try JSONEncoder().encode(["legadoIOSLocalFile": relocated.absoluteString]), as: UTF8.self)
        let model = ReaderViewModel(database: database, client: ReplayHttpClient(), cacheDirectory: root.appendingPathComponent("cache"), preDownloadCount: { 0 }, now: { 1234 })
        model.prepareLocalBook = { _ in restored }
        await model.load(bookURL: original.bookUrl)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.pagination?.text.string.contains("正文") == true)
        let chapters = try await ChapterRepository(database: database).list(bookUrl: original.bookUrl)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertTrue(chapters.allSatisfy { $0.bookUrl == original.bookUrl })
    }

    @MainActor
    func testCloseWaitsForInFlightSyncAndSendsLatestProgress() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/reader-close-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("book.txt")
        try Data("第一章 开始\n正文。\n第二章 后续\n下章正文。".utf8).write(to: file)
        let parsed = try LocalBook.parse(url: file)
        let database = try AppDatabase.inMemory()
        let book = try await LocalBook.save(book: parsed.book, chapters: parsed.chapters, database: database)
        let model = ReaderViewModel(database: database, client: ReplayHttpClient(), cacheDirectory: root.appendingPathComponent("cache"), preDownloadCount: { 0 }, now: { 1234 })
        await model.load(bookURL: book.bookUrl)
        var resumeNetwork: CheckedContinuation<Void, Never>?
        var events: [(Bool, Int)] = []
        model.synchronizeWebDav = { book, exiting in
            events.append((exiting, book.durChapterIndex))
            if !exiting { await withCheckedContinuation { resumeNetwork = $0 } }
            return nil
        }
        let network = Task { await model.syncWebDavProgress() }
        while resumeNetwork == nil { await Task.yield() }
        var next = BookProgress(book: book); next.durChapterIndex = 1
        await model.acceptWebDavProgress(next)
        let close = Task { await model.close() }
        while !model.closedWebDav { await Task.yield() }
        resumeNetwork?.resume()
        await network.value
        await close.value
        XCTAssertEqual(events.map { $0.0 }, [false, true])
        XCTAssertEqual(events.last?.1, 1)
    }
}
