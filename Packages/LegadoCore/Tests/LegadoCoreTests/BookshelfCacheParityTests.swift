import XCTest
@testable import LegadoCore

final class BookshelfCacheParityTests: XCTestCase {
    func testPinUpdatesReadTimeWithoutChangingGroupSort() async throws {
        let db = try AppDatabase.inMemory()
        var group = BookGroupRow(); group.groupId = 1; group.bookSort = 0
        try await BookGroupRepository(database: db).insert(group)
        let repository = BookshelfRepository(database: db)
        var first = BookRow(); first.bookUrl = "first"; first.name = "First"; first.group = 1; first.durChapterTime = 1000
        var second = first; second.bookUrl = "second"; second.name = "Second"; second.durChapterTime = 1
        try await repository.upsert([first, second])
        let saved = try await repository.saveAtTop(second)
        XCTAssertGreaterThan(saved.durChapterTime, first.durChapterTime)
        let sorted = try await repository.list(groupID: 1, sort: .lastRead)
        XCTAssertEqual(sorted.first?.bookUrl, second.bookUrl)
        let storedGroup = try await BookGroupRepository(database: db).get(groupID: 1)
        XCTAssertEqual(storedGroup?.bookSort, 0)
    }

    func testRefreshFailuresRetainBookAndCause() async {
        let report = await BookshelfRefresh.run(bookURLs: ["missing", "timeout", "parse"]) { url in
            switch url {
            case "missing": throw BookshelfRefresh.UpdateError.missingSource
            case "timeout": throw URLError(.timedOut)
            default: throw WebBookError.emptyToc
            }
        }
        let categories = Dictionary(uniqueKeysWithValues: report.failures.map { ($0.bookURL, $0.kind) })
        XCTAssertEqual(categories["missing"], .missingSource)
        XCTAssertEqual(categories["timeout"], .timeout)
        XCTAssertEqual(categories["parse"], .parsing)
        XCTAssertTrue(report.updated.isEmpty)
    }

    func testAddingAtTopPreservesExistingChaptersAndHandlesMinimumOrder() async throws {
        let db = try AppDatabase.inMemory()
        let repository = BookshelfRepository(database: db)
        var first = BookRow(); first.bookUrl = "fixture:first"; first.name = "First"; first.order = -4
        try await repository.insert(first)
        var next = BookRow(); next.bookUrl = "fixture:next"; next.name = "Next"
        let saved = try await repository.saveAtTop(next)
        XCTAssertEqual(saved.order, -5)
        var chapter = BookChapterRow(); chapter.bookUrl = next.bookUrl; chapter.url = "chapter"; chapter.title = "Chapter"
        try await ChapterRepository(database: db).insert(chapter)
        next = saved; next.order = Int.min
        try await repository.update(next)
        let readded = try await repository.saveAtTop(next)
        XCTAssertEqual(readded.order, -1)
        let chapters = try await ChapterRepository(database: db).list(bookUrl: next.bookUrl)
        XCTAssertEqual(chapters.count, 1)
        let sorted = try await repository.list(sort: .manual)
        XCTAssertEqual(sorted.map(\.bookUrl), [next.bookUrl, first.bookUrl])
    }

    func testLocalTextIsAlwaysCachedAndCleanupRetainsRenamedBookAndUnrelatedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var book = Book(); book.bookUrl = "file:///sample.txt"; book.origin = "loc_book"; book.name = "Before"; book.type = 264
        var chapter = BookChapter(); chapter.url = "chapter"; chapter.title = "One"
        XCTAssertTrue(BookHelp.hasContent(directory: root, book: book, chapter: chapter))
        try BookHelp.save("Retained", directory: root, book: book, chapter: chapter)
        let oldFolder = BookHelp.contentURL(directory: root, book: book, chapter: chapter).deletingLastPathComponent()
        let stale = root.appendingPathComponent("book_cache/stale")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("Delete".utf8).write(to: stale.appendingPathComponent("data"))
        let unrelated = root.appendingPathComponent("unrelated.txt")
        try Data("Keep".utf8).write(to: unrelated)
        book.name = "After"
        XCTAssertEqual(try BookHelp.clearInvalidCache(directory: root, books: [book]), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldFolder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertEqual(try BookHelp.content(directory: root, book: book, chapter: chapter), "Retained")
    }

    func testCleanupPreservesEpubAndDoesNotFollowSymbolicLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = root.appendingPathComponent("epub/kept.epub")
        let orphan = root.appendingPathComponent("epub/orphan.epub")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        var book = Book(); book.bookUrl = "file:///kept.epub"; book.origin = "loc_book"; book.originName = "kept.epub"
        let cache = root.appendingPathComponent("book_cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("orphan-link"), withDestinationURL: content)
        XCTAssertEqual(try BookHelp.clearInvalidCache(directory: root, books: [book]), 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: content.path))
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: content)
        XCTAssertThrowsError(try BookHelp.clearInvalidCache(directory: root, books: []))
        XCTAssertTrue(FileManager.default.fileExists(atPath: content.path))
    }

    func testChapterUpdateClaimIsAtomicThrottledAndOnlyNearEnd() async throws {
        let db = try AppDatabase.inMemory()
        let repository = BookshelfRepository(database: db)
        var book = BookRow(); book.bookUrl = "fixture:book"; book.name = "Book"
        book.origin = "https://fixture.test"; book.canUpdate = true; book.totalChapterNum = 10; book.durChapterIndex = 6
        try await repository.insert(book)
        var claimed = try await repository.claimChapterUpdate(bookURL: book.bookUrl, now: 1_000_000)
        XCTAssertFalse(claimed)
        book.durChapterIndex = 7
        try await repository.update(book)
        claimed = try await repository.claimChapterUpdate(bookURL: book.bookUrl, now: 1_000_000)
        XCTAssertTrue(claimed)
        claimed = try await repository.claimChapterUpdate(bookURL: book.bookUrl, now: 1_599_999)
        XCTAssertFalse(claimed)
        claimed = try await repository.claimChapterUpdate(bookURL: book.bookUrl, now: 1_600_000)
        XCTAssertTrue(claimed)
        claimed = try await repository.claimChapterUpdate(bookURL: book.bookUrl, now: 1_600_000)
        XCTAssertFalse(claimed)
        book.origin = "loc_book"; book.type |= 256
        try await repository.update(book)
        claimed = try await repository.claimChapterUpdate(bookURL: book.bookUrl, now: 2_200_000)
        XCTAssertFalse(claimed)
    }
}
