import XCTest
@testable import LegadoCore

final class BookshelfAdvancedTests: XCTestCase {
    func testBuiltinGroupsAndMasks() {
        XCTAssertEqual(BuiltinBookGroup.all.rawValue, -1)
        XCTAssertEqual(BuiltinBookGroup.local.rawValue, -2)
        XCTAssertEqual(BuiltinBookGroup.audio.rawValue, -3)
        XCTAssertEqual(BuiltinBookGroup.networkUngrouped.rawValue, -4)
        XCTAssertEqual(BuiltinBookGroup.localUngrouped.rawValue, -5)
        XCTAssertEqual(BuiltinBookGroup.video.rawValue, -6)
        XCTAssertEqual(BuiltinBookGroup.error.rawValue, -11)
        var book = BookRow()
        XCTAssertTrue(BookGroupMembership.contains(book, groupID: -4, customMask: 3))
        book.group = 2
        XCTAssertFalse(BookGroupMembership.contains(book, groupID: -4, customMask: 3))
        XCTAssertTrue(BookGroupMembership.contains(book, groupID: 2, customMask: 3))
        book.type |= 1024
        XCTAssertFalse(BookGroupMembership.contains(book, groupID: -1, customMask: 3))
    }

    func testGroupMoveAndDeletionPreserveUnrelatedBits() async throws {
        let db = try AppDatabase.inMemory()
        let books = BookshelfRepository(database: db)
        let groups = BookGroupRepository(database: db)
        var book = BookRow(); book.bookUrl = "book"; book.group = 5
        try await books.insert(book)
        var group = BookGroupRow(); group.groupId = 2
        try await groups.insert(group)
        try await books.move(bookURLs: ["book"], from: 1, to: 2)
        let moved = try await books.get(bookUrl: "book")
        XCTAssertEqual(moved?.group, 6)
        try await groups.removeCustomGroup(2)
        let remaining = try await books.get(bookUrl: "book")
        XCTAssertEqual(remaining?.group, 4)
    }

    func testCacheConcurrencyRetryAndFailureIsolation() async {
        let probe = DownloadProbe()
        let cache = CacheBook(maximumConcurrent: 2, retryLimit: 1)
        await cache.enqueue(bookURL: "book", chapters: Array(0..<6)) { index in
            try await probe.run(index)
        }
        await cache.waitUntilIdle()
        let states = await cache.snapshot()
        XCTAssertEqual(states.filter { $0.state == .completed }.count, 5)
        XCTAssertEqual(states.filter { $0.state == .failed }.count, 1)
        XCTAssertEqual(states.first { $0.chapterIndex == 0 }?.attempts, 2)
        let maximum = await probe.maximum
        XCTAssertLessThanOrEqual(maximum, 2)
        XCTAssertGreaterThan(maximum, 1)
    }

    func testExportReplacementRangeAndZipStructure() throws {
        var book = Book(now: 0); book.name = "书<&"; book.author = "作者"; book.bookUrl = "id"
        var chapter = BookChapter(); chapter.title = "第一章"; chapter.index = 0
        var rule = ReplaceRule(); rule.pattern = "旧"; rule.replacement = "新"; rule.scopeContent = true
        let exporter = BookExporter(book: book, chapters: [.init(chapter: chapter, content: "旧正文")], rules: [rule], createdAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(try exporter.txt(useReplace: false).contains("旧正文"))
        XCTAssertTrue(try exporter.txt(useReplace: false).contains("\n\n第一章\n　　旧正文"))
        XCTAssertTrue(try exporter.txt(useReplace: true).contains("新正文"))
        XCTAssertThrowsError(try exporter.txt(range: 1...2))
        let data = try exporter.epub(cover: .init(data: Data([1, 2, 3]), mediaType: "image/jpeg"))
        XCTAssertEqual(String(decoding: data[30..<38], as: UTF8.self), "mimetype")
        XCTAssertEqual(data[8], 0)
        let zip = try ZipReader(data: data)
        XCTAssertEqual(try zip.readEntry("mimetype"), Data("application/epub+zip".utf8))
        XCTAssertNotNil(try zip.readEntry("META-INF/container.xml"))
        XCTAssertNotNil(try zip.readEntry("OEBPS/Images/cover.jpg"))
        let opf = String(decoding: try XCTUnwrap(zip.readEntry("OEBPS/content.opf")), as: UTF8.self)
        XCTAssertTrue(opf.contains("书&lt;&amp;"))
        XCTAssertTrue(opf.contains("<itemref idref=\"chapter_0\"/>"))
        XCTAssertTrue(opf.contains("1970-01-01T00:00:00Z"))
    }

    func testEpubRangeAndSpineOrder() throws {
        var book = Book(now: 0); book.bookUrl = "id"
        let items: [BookExporter.Chapter] = [2, 0, 1].map {
            var chapter = BookChapter(); chapter.index = $0; chapter.title = "第\($0)章"
            return .init(chapter: chapter, content: "正文\($0)")
        }
        let exporter = BookExporter(book: book, chapters: items, createdAt: Date(timeIntervalSince1970: 0))
        let zip = try ZipReader(data: exporter.epub(range: 1...2))
        XCTAssertNil(try zip.readEntry("OEBPS/Text/chapter_0.html"))
        let opf = String(decoding: try XCTUnwrap(zip.readEntry("OEBPS/content.opf")), as: UTF8.self)
        XCTAssertTrue(opf.contains("<itemref idref=\"chapter_1\"/><itemref idref=\"chapter_2\"/>"))
        XCTAssertLessThan(try XCTUnwrap(opf.range(of: "id=\"chapter_1\"")) .lowerBound,
                          try XCTUnwrap(opf.range(of: "id=\"chapter_2\"")) .lowerBound)
    }

    func testChapterCacheFilename() {
        var chapter = BookChapter(); chapter.index = 12; chapter.title = "abc"
        XCTAssertEqual(BookHelp.chapterFileName(chapter), "00012-3cd24fb0d6963f7d.nb")
    }

    func testCachedContentSurvivesBookRename() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/tmp/b10-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var book = Book(now: 0); book.bookUrl = "book"; book.name = "旧名"
        var chapter = BookChapter(); chapter.index = 0; chapter.title = "章"
        try BookHelp.save("正文", directory: directory, book: book, chapter: chapter)
        book.name = "新名"
        XCTAssertEqual(try BookHelp.content(directory: directory, book: book, chapter: chapter), "正文")
    }

    func testRefreshConcurrencyAndFailureIsolation() async {
        let probe = DownloadProbe()
        let report = await BookshelfRefresh.run(bookURLs: (0..<6).map(String.init), maximumConcurrent: 2) {
            try await probe.run(Int($0)!)
        }
        XCTAssertEqual(report.updated.count, 4)
        XCTAssertEqual(Set(report.failures.map(\.bookURL)), ["0", "5"])
        let maximum = await probe.maximum
        XCTAssertLessThanOrEqual(maximum, 2)
        XCTAssertFalse(report.cancelled)
    }

    func testPauseCancelAndResume() async {
        let gate = DownloadGate()
        let cache = CacheBook(maximumConcurrent: 1)
        await cache.enqueue(bookURL: "book", chapters: [0, 1]) { _ in await gate.enter() }
        await gate.waitForStart()
        await cache.pause(bookURL: "book")
        let paused = await cache.snapshot()
        XCTAssertTrue(paused.allSatisfy { $0.state == .paused })
        await gate.release()
        await cache.waitUntilIdle()
        await cache.resume(bookURL: "book")
        await cache.waitUntilIdle()
        let resumed = await cache.snapshot()
        XCTAssertTrue(resumed.allSatisfy { $0.state == .completed })
        await cache.enqueue(bookURL: "other", chapters: [0, 1]) { _ in throw URLError(.cancelled) }
        await cache.cancel(bookURL: "other")
        await cache.waitUntilIdle()
        let cancelled = await cache.snapshot().filter { $0.bookURL == "other" }
        XCTAssertTrue(cancelled.allSatisfy { $0.state == .cancelled })
    }

    func testChapterUpdatePreservesMetadataAndReading() async throws {
        let db = try AppDatabase.inMemory()
        let books = BookshelfRepository(database: db)
        var book = BookRow(); book.bookUrl = "book"; book.name = "编辑名"; book.durChapterIndex = 7; book.type |= 16
        try await books.insert(book)
        var chapter = BookChapterRow(); chapter.bookUrl = "book"; chapter.url = "chapter"; chapter.title = "章"
        try await books.saveChapterUpdate(bookURL: "book", chapters: [chapter], checkedAt: 123)
        let updated = try await books.get(bookUrl: "book")
        XCTAssertEqual(updated?.name, "编辑名")
        XCTAssertEqual(updated?.durChapterIndex, 0)
        XCTAssertEqual(updated?.durChapterTitle, "章")
        XCTAssertEqual(updated?.lastCheckCount, 1)
        XCTAssertEqual(updated?.latestChapterTime, 123)
        XCTAssertEqual(updated!.type & 16, 0)
    }
}

private actor DownloadGate {
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func enter() async {
        started = true
        startWaiters.forEach { $0.resume() }; startWaiters.removeAll()
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }
    func waitForStart() async {
        if !started { await withCheckedContinuation { startWaiters.append($0) } }
    }
    func release() {
        released = true
        waiters.forEach { $0.resume() }; waiters.removeAll()
    }
}

private actor DownloadProbe {
    var active = 0
    var maximum = 0
    var attempts: [Int: Int] = [:]
    func run(_ index: Int) async throws {
        active += 1; maximum = max(maximum, active)
        attempts[index, default: 0] += 1
        let attempt = attempts[index]!
        defer { active -= 1 }
        for _ in 0..<20 { await Task.yield() }
        if index == 5 || (index == 0 && attempt == 1) { throw URLError(.timedOut) }
    }
}
