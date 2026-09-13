import XCTest
import GRDB
@testable import LegadoCore

final class EntityCompatibilityTests: XCTestCase {
    func testNewEntitiesRoundTrip() throws {
        func check<T: Codable & Equatable>(_ value: T) throws {
            XCTAssertEqual(try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value)), value)
        }
        try check(SearchKeyword())
        try check(HighlightRule())
        try check(Server())
        try check(KeyboardAssist())
        try check(RuleSub())
        try check(Cache())
        try check(AutoTaskRule())
        try check(BookMemo())
        try check(BookSourceCheckStateRow())
    }

    func testV7PreservesV6Data() throws {
        let queue = try DatabaseQueue()
        let migrator = Migrations.migrator()
        try migrator.migrate(queue, upTo: "v6")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO book_groups (groupId, groupName, `order`) VALUES (7, '保留', 0)")
        }
        try migrator.migrate(queue)
        try queue.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT groupName FROM book_groups WHERE groupId = 7"), "保留")
            for table in ["search_keywords", "highlightRules", "servers", "keyboardAssists", "ruleSubs", "caches", "auto_task_rules", "book_memos", "book_source_check_states"] {
                XCTAssertTrue(try db.tableExists(table), table)
            }
        }
    }

    func testAndroidFieldNamesAndDefaults() throws {
        let decoder = GsonJSONDecoder(now: { 123 })
        let rule = try decoder.decode(HighlightRule.self, from: Data(#"{"id":7,"uuid":"stable","order":19,"isRegex":true,"applyToBody":false}"#.utf8))
        XCTAssertEqual(rule.order, 19)
        XCTAssertTrue(rule.isRegex)
        XCTAssertFalse(rule.applyToBody)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any])
        XCTAssertEqual(fields["order"] as? Int, 19)
        XCTAssertNil(fields["sortOrder"])
        XCTAssertEqual(try decoder.decode(SearchKeyword.self, from: Data("{}".utf8)).lastUseTime, 123)
        XCTAssertEqual(try decoder.decode(Server.self, from: Data("{}".utf8)).id, 123)
        XCTAssertEqual(try decoder.decode(BookMemo.self, from: Data("{}".utf8)).updatedAt, 123)
        let subscription = try decoder.decode(RuleSub.self, from: Data("{}".utf8))
        XCTAssertEqual(subscription.id, 123)
        XCTAssertEqual(subscription.update, 123)
        let task = try decoder.decode(AutoTaskRule.self, from: Data("{}".utf8))
        XCTAssertEqual(task.cron, "*/30 * * * *")
        XCTAssertTrue(task.enabledCookieJar)
    }

    func testRuleSubZeroIDsGenerateAndKeyboardKeysAreScopedByType() async throws {
        let database = try AppDatabase.inMemory()
        let rules = RuleSubRepository(database: database)
        var first = RuleSub(); first.name = "first"
        var second = RuleSub(); second.name = "second"
        try await rules.upsert([first, second])
        let stored = try await rules.all()
        XCTAssertEqual(stored.count, 2)
        XCTAssertFalse(stored.contains { $0.id == 0 })
        var key = KeyboardAssist(); key.key = "key"; key.value = "first"
        var other = key; other.type = 1; other.value = "second"
        let keyboard = KeyboardAssistRepository(database: database)
        try await keyboard.upsert([key, other])
        let keys = try await keyboard.all()
        XCTAssertEqual(keys.filter { $0.key == "key" }.count, 2)
    }

    func testHistoryCountsAndCacheDeadline() async throws {
        let database = try AppDatabase.inMemory()
        let history = SearchKeywordRepository(database: database)
        try await history.record("  书名 ", at: 1)
        try await history.record("书名", at: 3)
        try await history.record("作者", at: 2)
        let values = try await history.history()
        XCTAssertEqual(values.map(\.word), ["书名", "作者"])
        XCTAssertEqual(values.first?.usage, 2)
        var cache = Cache(); cache.key = "v_source"; cache.value = "value"; cache.deadline = 10
        let repository = CacheRepository(database: database)
        try await repository.upsert(cache)
        let before = try await repository.value(forKey: cache.key, at: 9)
        let atDeadline = try await repository.value(forKey: cache.key, at: 10)
        XCTAssertEqual(before, "value")
        XCTAssertNil(atDeadline)
    }

    func testCompleteAndroidArchiveImportsAndExports() async throws {
        let expected = [
            "bookshelf.json", "bookGroup.json", "bookMemo.json", "bookmark.json", "highlight.json", "highlightRule.json",
            "bookSource.json", "rssSources.json", "rssStar.json", "sourceSub.json", "cookies.json", "runtimeSourceCache.json",
            "replaceRule.json", "txtTocRule.json", "httpTTS.json", "keyboardAssists.json", "dictRule.json", "autoTask.json",
            "servers.json", "directLinkUploadRule.json", "coverRule.json", "readRecord.json", "searchHistory.json",
            "readConfig.json", "shareReadConfig.json", "themeConfig.json", "config.xml", "videoConfig.xml"
        ]
        var files = Dictionary(uniqueKeysWithValues: expected.map { ($0, "[]") })
        files["config.xml"] = "<map/>"; files["videoConfig.xml"] = "<map/>"
        files["bookMemo.json"] = #"[{"bookUrl":"book","content":"memo","updatedAt":9}]"#
        files["highlight.json"] = #"[{"time":8,"bookUrl":"book"}]"#
        files["highlightRule.json"] = #"[{"id":0,"uuid":"uuid","order":17,"isRegex":true}]"#
        files["sourceSub.json"] = #"[{"id":3,"name":"规则","url":"https://example.test/rules","js":"script","showRule":"show","sourceUrl":"source"}]"#
        files["keyboardAssists.json"] = #"[{"type":1,"key":"key","value":"value","serialNo":4}]"#
        files["autoTask.json"] = #"[{"id":"task","enable":false,"script":"script"}]"#
        files["servers.json"] = #"[{"id":2,"name":"server","type":"WEBDAV","config":"{\"url\":\"https://example.test\",\"username\":\"user\",\"password\":\"synthetic\"}"}]"#
        files["searchHistory.json"] = #"[{"word":"word","usage":4,"lastUseTime":6}]"#
        files["cookies.json"] = #"[{"url":"https://example.test","cookie":"synthetic=value"}]"#
        files["runtimeSourceCache.json"] = #"[{"key":"v_source","value":"value","deadline":0}]"#
        files["themeConfig.json"] = #"{"preserved":"theme"}"#
        let database = try AppDatabase.inMemory()
        let importer = BackupImporter(database: database, localDeviceID: "local", now: { 10 })
        let report = try await importer.importArchive(BackupReviewTests.archive(files))
        XCTAssertTrue(report.failures.isEmpty, "\(report.failures)")
        XCTAssertEqual(Set(report.importedFiles), Set(expected))
        XCTAssertTrue(report.skippedFiles.isEmpty)
        let repeated = try await importer.importArchive(BackupReviewTests.archive(files))
        XCTAssertTrue(repeated.failures.isEmpty, "\(repeated.failures)")
        let highlights = try await HighlightRuleRepository(database: database).all()
        XCTAssertEqual(highlights.count, 1)
        XCTAssertEqual(highlights.first?.order, 0)
        let currentTheme = Data("[{\"themeName\":\"current\"}]".utf8)
        let exported = try await BackupExporter(database: database, now: { Date(timeIntervalSince1970: 1) }).export(includeSourceState: true, currentConfigurationFiles: ["themeConfig.json": currentTheme])
        let archive = try BackupArchive(data: exported)
        XCTAssertEqual(Set(archive.files.keys), Set(expected))
        XCTAssertEqual(archive.files["themeConfig.json"], currentTheme)
        let rule = try GsonJSONDecoder().decode([HighlightRule].self, from: archive.files["highlightRule.json"]!)
        XCTAssertTrue(rule[0].isRegex)
        XCTAssertEqual(rule[0].order, 0)
        let restored = try await BackupImporter(database: AppDatabase.inMemory(), localDeviceID: "second").importArchive(exported)
        XCTAssertTrue(restored.failures.isEmpty, "\(restored.failures)")
    }

    func testInvalidRuntimeCacheAndCookieDoNotPartiallyWrite() async throws {
        let database = try AppDatabase.inMemory()
        let files = [
            "runtimeSourceCache.json": #"[{"key":"v_valid","value":"ok","deadline":0},{"key":"not-runtime","value":"bad","deadline":0}]"#,
            "cookies.json": #"[{"url":"https://example.test","cookie":"valid"},{"url":3,"cookie":"bad"}]"#
        ]
        let report = try await BackupImporter(database: database, localDeviceID: "local").importArchive(BackupReviewTests.archive(files))
        XCTAssertEqual(report.failures.count, 2)
        let caches = try await CacheRepository(database: database).all()
        let cookies = try await CookieRepository(database: database).all()
        XCTAssertTrue(caches.isEmpty)
        XCTAssertTrue(cookies.isEmpty)
    }

    func testRuleSubParsingAndInjectedURL() async throws {
        let importer = SourceImporter(now: { 90 })
        let text = #"{"name":"name","url":"https://example.test/rules","type":2,"updateInterval":4,"silentUpdate":true}"#
        let values = try importer.parseRuleSubs(text)
        XCTAssertEqual(values[0].id, 90)
        XCTAssertEqual(values[0].type, 2)
        XCTAssertTrue(values[0].silentUpdate)
        XCTAssertThrowsError(try importer.parseRuleSubs(#"{"url":""}"#))
        XCTAssertThrowsError(try importer.parseRuleSubs("null"))
        let url = URL(string: "https://example.test/subscription")!
        let remote = try await importer.importRuleSubs(from: url, client: SubscriptionClient(body: text))
        XCTAssertEqual(remote, values)
        do {
            _ = try await importer.importRuleSubs(from: url, client: SubscriptionClient(body: text, status: 503))
            XCTFail("HTTP failure must propagate")
        } catch RuleSubImportError.httpStatus(503) {}
        var subscription = values[0]
        subscription.type = 0
        let database = try AppDatabase.inMemory()
        let count = try await RuleSubRepository(database: database).refresh(subscription, client: SubscriptionClient(body: #"[{"bookSourceUrl":"https://example.test","bookSourceName":"source"}]"#), at: 100)
        XCTAssertEqual(count, 1)
        let sources = try await BookSourceRepository(database: database).all()
        XCTAssertEqual(sources.first?.bookSourceName, "source")
    }
}

private struct SubscriptionClient: HttpClient {
    let body: String
    var status = 200
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        HttpResponse(status: status, body: Data(body.utf8), finalURL: request.url)
    }
}

extension EntityCompatibilityTests {
    func testReviewMemoOnlyRestoredBooksAndNewerTimestamp() async throws {
        let db = try AppDatabase.inMemory()
        for name in ["old", "new", "equal", "excluded"] {
            var book = BookRow(); book.bookUrl = name; book.name = name
            try await BookshelfRepository(database: db).upsert(book)
            var memo = BookMemo(); memo.bookUrl = name; memo.content = "local"; memo.updatedAt = 10
            try await BookMemoRepository(database: db).upsert(memo)
        }
        let files = ["bookshelf.json": #"[{"bookUrl":"old","name":"old"},{"bookUrl":"new","name":"new"},{"bookUrl":"equal","name":"equal"}]"#,
                     "bookMemo.json": #"[{"bookUrl":"old","content":"backup","updatedAt":9},{"bookUrl":"new","content":"backup","updatedAt":11},{"bookUrl":"equal","content":"backup","updatedAt":10},{"bookUrl":"excluded","content":"backup","updatedAt":99},{"bookUrl":"orphan","updatedAt":99}]"#]
        let report = try await BackupImporter(database: db, localDeviceID: "local").importArchive(BackupReviewTests.archive(files))
        XCTAssertTrue(report.failures.isEmpty)
        let memos = try await BookMemoRepository(database: db).all()
        XCTAssertEqual(memos.count, 4)
        XCTAssertEqual(memos.filter { $0.content == "backup" }.map(\.bookUrl), ["new"])
    }

    func testReviewLegacyHighlightsAndRestoreOrder() async throws {
        let db = try AppDatabase.inMemory()
        var book = BookRow(); book.bookUrl = "book"; book.name = "name"; book.author = "author"
        try await BookshelfRepository(database: db).upsert(book)
        var chapter = BookChapterRow(); chapter.bookUrl = "book"; chapter.url = "chapter"; chapter.title = "title"; chapter.index = 2
        try await ChapterRepository(database: db).upsert(chapter)
        let files = ["bookshelf.json": #"[{"bookUrl":"book","name":"name","author":"author"}]"#,
                     "bookGroup.json": "[]", "bookmark.json": "[]", "bookMemo.json": "[]",
                     "highlight.json": #"[{"time":1,"bookName":"name","bookAuthor":"author","chapterIndex":2,"chapterName":"title","bgColor":-256,"textColor":-16777216},{"time":2,"bookName":"name","bookAuthor":"author","chapterIndex":2,"chapterName":"different","style":"existing","bgColor":1}]"#]
        let report = try await BackupImporter(database: db, localDeviceID: "local").importArchive(BackupReviewTests.archive(files))
        XCTAssertEqual(report.importedFiles, ["bookshelf.json", "bookMemo.json", "bookmark.json", "highlight.json", "bookGroup.json"])
        let highlights = try await BookHighlightRepository(database: db).all().sorted { $0.time < $1.time }
        let first = try XCTUnwrap(highlights.first)
        XCTAssertEqual(first.bookUrl, "book"); XCTAssertEqual(first.chapterUrl, "chapter")
        let style = (try? JSONSerialization.jsonObject(with: Data(first.style.utf8))) as? [String: Any]
        XCTAssertEqual(style?["fill"] as? Int, -256); XCTAssertEqual(style?["textColor"] as? Int, -16777216)
        XCTAssertEqual(highlights.last?.chapterUrl, ""); XCTAssertEqual(highlights.last?.style, "existing")
    }

    func testReviewHighlightRulesReplaceNormalizeAndRejectDuplicateUUID() async throws {
        let db = try AppDatabase.inMemory()
        var old = HighlightRule(); old.uuid = "11111111-1111-1111-1111-111111111111"
        try await HighlightRuleRepository(database: db).upsert(old)
        let importer = BackupImporter(database: db, localDeviceID: "local")
        let json = #"[{"id":88,"uuid":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","order":99,"group":"  group  ","timeoutMillisecond":0},{"id":89,"uuid":"invalid","order":-3,"group":"  "}]"#
        let report = try await importer.importArchive(BackupReviewTests.archive(["highlightRule.json": json]))
        XCTAssertTrue(report.failures.isEmpty)
        let rules = try await HighlightRuleRepository(database: db).all().sorted { $0.order < $1.order }
        XCTAssertEqual(rules.map(\.order), [0, 1]); XCTAssertEqual(rules.first?.group, "group")
        XCTAssertEqual(rules.first?.timeoutMillisecond, 3000); XCTAssertFalse(rules.first?.style.isEmpty ?? true)
        XCTAssertTrue(rules.allSatisfy { UUID(uuidString: $0.uuid) != nil })
        let duplicate = #"[{"uuid":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"},{"uuid":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}]"#
        let rejected = try await importer.importArchive(BackupReviewTests.archive(["highlightRule.json": duplicate]))
        XCTAssertNotNil(rejected.failures["highlightRule.json"])
        let after = try await HighlightRuleRepository(database: db).all()
        XCTAssertEqual(after.count, 2)
        _ = try await importer.importArchive(BackupReviewTests.archive(["highlightRule.json": "[]"]))
        let empty = try await HighlightRuleRepository(database: db).all(); XCTAssertTrue(empty.isEmpty)
    }

    func testReviewKeyboardRestoreReplacesIncludingEmpty() async throws {
        let db = try AppDatabase.inMemory()
        var old = KeyboardAssist(); old.key = "old"
        try await KeyboardAssistRepository(database: db).upsert(old)
        let importer = BackupImporter(database: db, localDeviceID: "local")
        _ = try await importer.importArchive(BackupReviewTests.archive(["keyboardAssists.json": #"[{"key":"new","value":"new"}]"#]))
        let keys = try await KeyboardAssistRepository(database: db).all(); XCTAssertEqual(keys.map(\.key), ["new"])
        _ = try await importer.importArchive(BackupReviewTests.archive(["keyboardAssists.json": "[]"]))
        let empty = try await KeyboardAssistRepository(database: db).all(); XCTAssertTrue(empty.isEmpty)
    }

    func testReviewKeyboardDefaultsOnOpenOnlyWhenEmpty() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/tmp")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("keyboard-\(UUID().uuidString).sqlite").path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let first = try AppDatabase.file(at: path)
        let defaults = try await KeyboardAssistRepository(database: first).all().sorted { $0.serialNo < $1.serialNo }
        XCTAssertEqual(defaults.count, 32)
        XCTAssertEqual(defaults.first?.key, "@css:"); XCTAssertEqual(defaults.last?.value, #",{"webView": true}"#)
        try await first.write { db in try db.execute(sql: "DELETE FROM keyboardAssists") }
        let reopened = try AppDatabase.file(at: path)
        let restored = try await KeyboardAssistRepository(database: reopened).all(); XCTAssertEqual(restored.count, 32)
        try await reopened.write { db in try db.execute(sql: "DELETE FROM keyboardAssists") }
        var custom = KeyboardAssist(); custom.key = "custom"
        try await KeyboardAssistRepository(database: reopened).upsert(custom)
        let retained = try AppDatabase.file(at: path)
        let keys = try await KeyboardAssistRepository(database: retained).all(); XCTAssertEqual(keys.map(\.key), ["custom"])
    }

    func testReviewSubscriptionIDsAndTypes() async throws {
        let text = #"[{"url":"https://example.test/a"},{"url":"https://example.test/b"},{"url":"https://example.test/c"}]"#
        let rules = try SourceImporter(now: { 10 }).parseRuleSubs(text)
        XCTAssertEqual(Set(rules.map(\.id)).count, 3)
        let db = try AppDatabase.inMemory()
        let repository = RuleSubRepository(database: db)
        try await repository.saveImported(rules, at: 10)
        var collision = rules[0]; collision.url = "https://example.test/collision"
        var zero = rules[0]; zero.id = 0; zero.url = "https://example.test/zero"
        try await repository.saveImported([collision, zero], at: 10)
        let stored = try await repository.all()
        XCTAssertEqual(stored.count, 5)
        XCTAssertEqual(Set(stored.map(\.id)).count, 5)
        XCTAssertThrowsError(try SourceImporter().parseRuleSubs(#"{"url":"https://example.test","type":3}"#))
    }
}
