import XCTest
import GRDB
@testable import LegadoCore

final class SourceEditingTests: XCTestCase {
    func testDictRuleValidationUsesPortableErrorWithoutWriting() async throws {
        let repository = DictRuleRepository(database: try AppDatabase.inMemory())
        let before = try await repository.list()
        do {
            try await repository.save([DictRule(name: "valid", urlRule: "url"), DictRule(name: " \n")])
            XCTFail("应拒绝空名称")
        } catch {
            XCTAssertEqual(error as? DictRuleValidationError, .missingRequiredFields)
        }
        for rule in [DictRule(name: "", urlRule: "url"), DictRule(name: "valid", urlRule: "")] {
            do {
                try await repository.saveEdited(rule, replacing: nil)
                XCTFail("应拒绝缺失必填字段")
            } catch {
                XCTAssertEqual(error as? DictRuleValidationError, .missingRequiredFields)
            }
        }
        let after = try await repository.list()
        XCTAssertEqual(after, before)
    }
    func testAndroidDefaultRulesMatchEveryField() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Conformance/fixtures/default-rules")
        let txt = try JSONDecoder().decode([TxtTocRule].self, from: Data(contentsOf: root.appendingPathComponent("txtTocRule.json")))
        let dict = try JSONDecoder().decode([DictRule].self, from: Data(contentsOf: root.appendingPathComponent("dictRules.json")))
        XCTAssertEqual(TxtTocRule.builtIn.count, 26)
        XCTAssertEqual(DictRule.builtIn.count, 5)
        XCTAssertEqual(TxtTocRule.builtIn, txt)
        XCTAssertEqual(DictRule.builtIn, dict)
    }

    func testV4SeedsOnlyEmptyDictionaryTable() throws {
        for populated in [true, false] {
            let writer = try DatabaseQueue()
            try Migrations.migrator().migrate(writer, upTo: "v3")
            let custom = DictRule(name: "海词中文", urlRule: "custom", showRule: "custom-rule", enabled: false, sortNumber: 99)
            try writer.write { db in
                try db.execute(sql: "CREATE TABLE dictRules (name TEXT PRIMARY KEY, urlRule TEXT NOT NULL, showRule TEXT NOT NULL, enabled INTEGER NOT NULL, sortNumber INTEGER NOT NULL)")
                if populated { try custom.insert(db) }
            }
            try Migrations.migrator().migrate(writer, upTo: "v4")
            try writer.read { db in
                let actual = try DictRule.fetchAll(db)
                if populated { XCTAssertEqual(actual, [custom]) }
                else { XCTAssertEqual(actual, DictRule.builtIn) }
            }
        }
    }
    func testExportOrderNullAndRoundTrip() throws {
        var source = BookSource()
        source.bookSourceUrl = "https://example.invalid"
        source.bookSourceName = "<测试>"
        let text = try SourceExporter.bookSources([source])
        XCTAssertFalse(text.contains(": null"))
        XCTAssertTrue(text.contains("<测试>"))
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "bookSourceUrl")?.lowerBound),
                          try XCTUnwrap(text.range(of: "bookSourceName")?.lowerBound))
        XCTAssertEqual(try JSONDecoder().decode([BookSource].self, from: Data(text.utf8)), [source])
        let keys = text.components(separatedBy: "\n").filter { $0.hasPrefix("    \"") }
            .map { String($0.split(separator: "\"", omittingEmptySubsequences: false)[1]) }
        XCTAssertEqual(keys, ["bookSourceUrl", "bookSourceName", "bookSourceType", "customOrder", "enabled",
                              "enabledExplore", "enabledCookieJar", "lastUpdateTime", "respondTime", "weight",
                              "eventListener", "customButton"])
        var rule = ReplaceRule(now: 1)
        rule.pattern = "x"; rule.replacement = "y"
        XCTAssertEqual(try JSONDecoder().decode([ReplaceRule].self,
            from: Data(SourceExporter.replaceRules([rule]).utf8)), [rule])
    }

    func testDictMigrationAndRoundTrip() async throws {
        let database = try AppDatabase.inMemory()
        let repository = DictRuleRepository(database: database)
        var rule = DictRule(name: "测试", urlRule: "https://example.invalid/?q={{key}}")
        try await repository.save(rule)
        rule.enabled = false
        try await repository.save(rule)
        let rows = try await repository.list()
        XCTAssertEqual(rows.first(where: { $0.name == "测试" }), rule)
        try await repository.delete(name: rule.name)
        let remaining = try await repository.list()
        XCTAssertFalse(remaining.contains { $0.name == "测试" })
    }

    func testDebuggerFourStages() async throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Conformance/fixtures/webbook")
        let source = try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: fixtures.appendingPathComponent("source.json")))
        let client = ReplayHttpClient()
        let paths = ["/search?key=demo&page=1", "/book/1", "/toc/1", "/toc/2", "/read/1", "/read/1-2", "/read/1-3"]
        let files = ["search.html", "info.html", "toc1.html", "toc2.html", "content1.html", "content2.html", "content3.html"]
        for (path, file) in zip(paths, files) {
            let url = URL(string: "https://example.invalid" + path)!
            await client.enqueue(url: url, response: HttpResponse(status: 200,
                body: try Data(contentsOf: fixtures.appendingPathComponent(file)), finalURL: url))
        }
        var logs: [SourceDebugLog] = []
        for await log in SourceDebugger(client: client, clock: { 0 }).logs(source: source, key: "demo") { logs.append(log) }
        XCTAssertEqual(logs.filter { $0.message.contains("︾开始解析") }.map(\.message),
            ["[00:00.000] ︾开始解析搜索页", "[00:00.000] ︾开始解析详情页",
             "[00:00.000] ︾开始解析目录页", "[00:00.000] ︾开始解析正文页"])
        XCTAssertEqual(logs.last?.state, 1000)
        XCTAssertEqual(SourceDebugLog.format(milliseconds: 61_234, message: "测试"), "[01:01.234] 测试")
    }

    func testV4UpgradePreservesExistingRulesAndSource() throws {
        let writer = try DatabaseQueue()
        try Migrations.migrator().migrate(writer, upTo: "v3")
        try writer.write { db in
            var source = BookSourceRow(); source.bookSourceUrl = "existing"; source.enabled = false
            try source.insert(db)
            var rule = TxtTocRule.builtIn[0]; rule.name = "用户自定义"; rule.enable = false
            try rule.save(db)
        }
        try Migrations.migrator().migrate(writer, upTo: "v4")
        try writer.read { db in
            XCTAssertEqual(try BookSourceRow.fetchOne(db, key: "existing")?.enabled, false)
            XCTAssertEqual(try TxtTocRule.fetchOne(db, key: -1)?.name, "用户自定义")
            XCTAssertEqual(try DictRule.fetchAll(db), DictRule.builtIn)
        }
    }

    func testDebuggerFailureFinishesWithoutFollowingStages() async throws {
        var source = BookSource(); source.bookSourceUrl = "https://example.invalid"
        var logs: [SourceDebugLog] = []
        for await log in SourceDebugger(client: ReplayHttpClient(), clock: { 5 }).logs(source: source, key: "demo") {
            logs.append(log)
        }
        XCTAssertEqual(logs.last?.state, -1)
        XCTAssertFalse(logs.contains { $0.message.contains("︾开始解析详情页") })
        XCTAssertTrue(logs.allSatisfy { $0.message.hasPrefix("[00:00.000]") })
    }
}
