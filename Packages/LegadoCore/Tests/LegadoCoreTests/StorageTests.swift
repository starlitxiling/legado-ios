import XCTest
import GRDB
@testable import LegadoCore

final class StorageTests: XCTestCase {
    private func book(_ url: String, group: Int64 = 0, order: Int = 0, time: Int64 = 0) -> BookRow {
        var row = BookRow()
        row.bookUrl = url
        row.name = url
        row.group = group
        row.order = order
        row.durChapterTime = time
        return row
    }

    func testBaselineSchemaAndIndexes() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            for table in ["books", "chapters", "book_sources", "book_groups", "searchBooks", "replace_rules", "cookies", "readRecord", "bookmarks"] {
                XCTAssertTrue(tables.contains(table), table)
            }
            let indexes = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%'")
            XCTAssertEqual(Set(indexes), Set(["index_books_name_author", "index_chapters_bookUrl", "index_chapters_bookUrl_index", "index_book_sources_bookSourceUrl", "index_searchBooks_bookUrl", "index_searchBooks_origin", "index_replace_rules_id", "index_cookies_url", "index_readRecord_snapshot", "index_bookmarks_bookName_bookAuthor"]))
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations"), ["v1"])
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA foreign_keys"), 1)
            XCTAssertTrue(try db.columns(in: "books").contains { $0.name == "readConfig" })
            XCTAssertTrue(try db.columns(in: "replace_rules").contains { $0.name == "sortOrder" })
        }
    }

    func testBookshelfBitmaskSortingAndProgress() async throws {
        let database = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: database)
        try await shelf.upsert([book("a", group: 1, order: 2, time: 10), book("b", group: 3, order: 1, time: 20), book("c", group: 2)])
        var temporary = book("hidden", group: 1)
        temporary.type = 8 | 1024
        try await shelf.upsert(temporary)
        let grouped = try await shelf.list(groupID: 1, sort: .manual)
        XCTAssertEqual(grouped.map(\.bookUrl), ["b", "a"])
        let all = try await shelf.list()
        XCTAssertEqual(all.map(\.bookUrl), ["b", "a", "c"])
        let updated = try await shelf.updateProgress(bookUrl: "a", chapterIndex: 4, chapterPos: 70, chapterTitle: "第四章", readTime: 99)
        XCTAssertTrue(updated)
        let saved = try await shelf.get(bookUrl: "a")
        XCTAssertEqual(saved?.durChapterIndex, 4)
        XCTAssertEqual(saved?.durChapterPos, 70)
        XCTAssertEqual(saved?.durChapterTitle, "第四章")
        XCTAssertEqual(saved?.durChapterTime, 99)
        XCTAssertEqual(saved?.group, 1)
        let absent = try await shelf.updateProgress(bookUrl: "missing", chapterIndex: 0, chapterPos: 0, chapterTitle: nil, readTime: 1)
        XCTAssertFalse(absent)
    }

    func testBookImportReplacesIdentityAndCascadesOldChapters() async throws {
        let database = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: database)
        let chapters = ChapterRepository(database: database)
        try await shelf.insert(book("a"))
        var chapter = BookChapterRow()
        chapter.bookUrl = "a"
        chapter.url = "chapter"
        try await chapters.insert(chapter)
        var imported = book("b")
        imported.name = "a"
        imported.intro = "导入内容"
        try await shelf.replaceByIdentity([book("c"), imported])
        let rows = try await shelf.all()
        XCTAssertEqual(Set(rows.map(\.bookUrl)), ["b", "c"])
        let replacement = try await shelf.get(bookUrl: "b")
        XCTAssertEqual(replacement, imported)
        let oldChapters = try await chapters.list(bookUrl: "a")
        XCTAssertTrue(oldChapters.isEmpty)
        chapter.bookUrl = "b"
        try await chapters.insert(chapter)
        try await shelf.upsert(imported)
        let preserved = try await chapters.list(bookUrl: "b")
        XCTAssertEqual(preserved, [chapter])
    }

    func testChapterKeysCascadeAndUpsertPreservesChildren() async throws {
        let database = try AppDatabase.inMemory()
        let shelf = BookshelfRepository(database: database)
        let chapters = ChapterRepository(database: database)
        try await shelf.upsert([book("a"), book("b")])
        var first = BookChapterRow()
        first.bookUrl = "a"
        first.url = "shared"
        first.index = 2
        first.start = 9_000_000_000
        first.variable = "{\"x\":\"y\"}"
        var second = first
        second.bookUrl = "b"
        try await chapters.upsert([first, second])
        try await shelf.upsert(book("a", time: 10))
        let fetched = try await chapters.get(bookUrl: "a", index: 2)
        XCTAssertEqual(fetched, first)
        var duplicate = first
        duplicate.url = "different"
        try await chapters.insert(duplicate)
        let replaced = try await chapters.list(bookUrl: "a")
        XCTAssertEqual(replaced, [duplicate])
        let deleted = try await shelf.delete(book("a"))
        XCTAssertTrue(deleted)
        let remaining = try await chapters.all()
        XCTAssertEqual(remaining, [second])
        do { try await chapters.insert(first); XCTFail("孤立章节必须被拒绝") }
        catch let error as DatabaseError { XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT) }
    }

    func testChapterListAndAtomicReplacement() async throws {
        let database = try AppDatabase.inMemory()
        try await BookshelfRepository(database: database).upsert(book("a"))
        let repository = ChapterRepository(database: database)
        var first = BookChapterRow()
        first.bookUrl = "a"
        first.url = "one"
        first.index = 1
        var second = first
        second.url = "two"
        second.index = 2
        try await repository.replaceAll(bookUrl: "a", chapters: [second, first])
        let sorted = try await repository.list(bookUrl: "a")
        XCTAssertEqual(sorted, [first, second])
        var replacement = first
        replacement.url = "replacement"
        try await repository.replaceAll(bookUrl: "a", chapters: [first, replacement])
        let after = try await repository.list(bookUrl: "a")
        XCTAssertEqual(after, [replacement])
        second.bookUrl = "other"
        do { try await repository.replaceAll(bookUrl: "a", chapters: [second]); XCTFail("不能替换其他书籍章节") }
        catch { }
        try await repository.replaceAll(bookUrl: "a", chapters: [])
        let empty = try await repository.list(bookUrl: "a")
        XCTAssertTrue(empty.isEmpty)
    }

    func testSourcesSearchCacheAndCascade() async throws {
        let database = try AppDatabase.inMemory()
        let sources = BookSourceRepository(database: database)
        let cache = SearchCacheRepository(database: database)
        var source = BookSourceRow()
        source.bookSourceUrl = "source"
        source.ruleSearch = "{\"bookList\":\".book\"}"
        source.mainJs = "function search() {}"
        source.enabledCookieJar = nil
        source.customOrder = 2
        var disabled = source
        disabled.bookSourceUrl = "disabled"
        disabled.enabled = false
        disabled.customOrder = 0
        try await sources.upsert([source, disabled])
        let enabled = try await sources.list(enabled: true)
        XCTAssertEqual(enabled, [source])
        let ordered = try await sources.list()
        XCTAssertEqual(ordered.map(\.bookSourceUrl), ["disabled", "source"])
        var result = SearchBookRow()
        result.bookUrl = "result"
        result.origin = "source"
        result.time = 100
        try await cache.upsert(result)
        result.intro = "新简介"
        try await cache.upsert(result)
        try await sources.upsert(source)
        let cached = try await cache.get(bookUrl: "result")
        XCTAssertEqual(cached, result)
        try await cache.clearExpired(before: 100)
        let retained = try await cache.all()
        XCTAssertEqual(retained.count, 1)
        try await cache.clearExpired(before: 101)
        let expired = try await cache.all()
        XCTAssertTrue(expired.isEmpty)
        try await cache.upsert(result)
        _ = try await sources.delete(source)
        let deleted = try await cache.all()
        XCTAssertTrue(deleted.isEmpty)
    }

    func testReplaceRulesGeneratedIDsAndEnabledOrder() async throws {
        let repository = ReplaceRuleRepository(database: try AppDatabase.inMemory())
        var first = ReplaceRuleRow()
        first.pattern = "a"
        first.order = 2
        var second = first
        second.order = 1
        let inserted = try await repository.insert(first)
        let another = try await repository.insert(second)
        XCTAssertNotNil(inserted.id)
        XCTAssertNotEqual(inserted.id, another.id)
        let ordered = try await repository.list(enabled: true)
        XCTAssertEqual(ordered.map(\.id), [another.id, inserted.id])
        var disabled = another
        disabled.isEnabled = false
        try await repository.update(disabled)
        let enabled = try await repository.list(enabled: true)
        XCTAssertEqual(enabled, [inserted])
        _ = try await repository.delete(inserted)
        let missing = try await repository.get(id: inserted.id!)
        XCTAssertNil(missing)
    }

    func testGroupsCookiesAndBookmarksCRUD() async throws {
        let database = try AppDatabase.inMemory()
        let groups = BookGroupRepository(database: database)
        var group = BookGroupRow()
        group.groupId = 1 << 40
        group.groupName = "分组"
        try await groups.upsert(group)
        let fetchedGroup = try await groups.get(groupID: group.groupId)
        XCTAssertEqual(fetchedGroup, group)
        group.show = false
        try await groups.update(group)
        let groupList = try await groups.list()
        XCTAssertEqual(groupList, [group])
        _ = try await groups.delete(group)
        let cookies = CookieRepository(database: database)
        var cookie = CookieRow()
        cookie.url = "https://example.invalid/'"
        cookie.cookie = "sid=1"
        try await cookies.upsert(cookie)
        cookie.cookie = "sid=2"
        try await cookies.upsert(cookie)
        let fetchedCookie = try await cookies.get(url: cookie.url)
        XCTAssertEqual(fetchedCookie, cookie)
        _ = try await cookies.delete(cookie)
        let bookmarks = BookmarkRepository(database: database)
        var mark = BookmarkRow()
        mark.time = 9_000_000_000
        mark.bookName = "书"
        mark.bookAuthor = "作者"
        mark.chapterIndex = 2
        try await bookmarks.insert(mark)
        mark.content = "笔记"
        try await bookmarks.update(mark)
        let list = try await bookmarks.list(bookName: "书", bookAuthor: "作者")
        XCTAssertEqual(list, [mark])
        _ = try await bookmarks.delete(mark)
        let absent = try await bookmarks.get(time: mark.time)
        XCTAssertNil(absent)
    }

    func testReplaceRuleGroupsMatchWholeNormalizedTokens() async throws {
        let repository = ReplaceRuleRepository(database: try AppDatabase.inMemory())
        let groups: [String?] = [" A；B,C，D;E ", "AB", "\tA\n", nil, "", " \t\n\u{00A0}\u{3000}", " 未分组 ", ",;；", "A_B", "A%B", "O'Brien"]
        var rows: [ReplaceRuleRow] = []
        for (index, group) in groups.enumerated() {
            var row = ReplaceRuleRow()
            row.id = Int64(index + 1)
            row.group = group
            row.order = -index
            row.isEnabled = index != 2
            rows.append(row)
        }
        try await repository.upsert(rows)
        let matches = try await repository.list(groupName: "\u{3000}A\u{00A0}")
        XCTAssertEqual(matches.map(\.id), [3, 1])
        for name in ["B", "C", "D", "E"] {
            let result = try await repository.list(groupName: name)
            XCTAssertEqual(result.map(\.id), [1])
        }
        for (name, id) in [("AB", 2), ("A_B", 9), ("A%B", 10), ("O'Brien", 11)] {
            let result = try await repository.list(groupName: name)
            XCTAssertEqual(result.map(\.id), [Int64(id)])
        }
        for blank in ["", " \t\n\u{3000}"] {
            let result = try await repository.list(groupName: blank)
            XCTAssertTrue(result.isEmpty)
        }
        let ungrouped = try await repository.listUngrouped()
        XCTAssertEqual(Set(ungrouped.compactMap(\.id)), [4, 5, 6, 7])
    }

    func testFileDatabaseSuspendsAndResumesWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try AppDatabase.file(at: directory.appendingPathComponent("suspend.sqlite").path)
        XCTAssertTrue(database.writer.configuration.observesSuspensionNotifications)
        let repository = BookshelfRepository(database: database)
        try await repository.upsert(book("before"))
        database.suspend()
        defer { database.resume() }
        do {
            try await repository.upsert(book("during"))
            XCTFail("挂起期间写入必须失败")
        } catch let error as DatabaseError {
            XCTAssertTrue([ResultCode.SQLITE_ABORT, .SQLITE_INTERRUPT].contains(error.resultCode))
        }
        database.resume()
        try await repository.upsert(book("after"))
        let rows = try await repository.all()
        XCTAssertEqual(Set(rows.map(\.bookUrl)), ["before", "after"])
    }

    func testReadRecordCompositeIdentityAndAccumulation() async throws {
        let repository = ReadProgressRepository(database: try AppDatabase.inMemory())
        var record = ReadRecordRow()
        record.deviceId = "device"
        record.bookName = "书"
        record.author = "作者"
        record.lastRead = 20
        record.lastChapterIndex = 4
        try await repository.record(record, elapsed: 10)
        var stale = record
        stale.lastRead = 10
        stale.lastChapterIndex = 1
        try await repository.record(stale, elapsed: 3)
        try await repository.record(stale, elapsed: -5)
        let saved = try await repository.get(deviceID: "device", bookName: "书", author: "作者")
        XCTAssertEqual(saved?.readTime, 13)
        XCTAssertEqual(saved?.lastChapterIndex, 4)
        var other = record
        other.author = "另一作者"
        try await repository.upsert(other)
        let list = try await repository.list(bookName: "书", author: "作者")
        XCTAssertEqual(list.count, 1)
        _ = try await repository.delete(other)
    }

    func testReadDurationConcurrentWrites() async throws {
        let repository = ReadProgressRepository(database: try AppDatabase.inMemory())
        let record = ReadRecordRow()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { try await repository.record(record, elapsed: 1) }
            }
            try await group.waitForAll()
        }
        let saved = try await repository.get(deviceID: "", bookName: "", author: "")
        XCTAssertEqual(saved?.readTime, 20)
    }

    func testFileDatabasePersistsAndMigrationIsIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("test.sqlite").path
        do {
            let database = try AppDatabase.file(at: path)
            XCTAssertTrue(database.writer is DatabasePool)
            try await BookshelfRepository(database: database).upsert(book("persisted"))
        }
        let reopened = try AppDatabase.file(at: path)
        let saved = try await BookshelfRepository(database: reopened).get(bookUrl: "persisted")
        XCTAssertEqual(saved?.bookUrl, "persisted")
    }
}
