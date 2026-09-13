import XCTest
import LegadoCore
@testable import SourceEditCheck

@MainActor
final class SourceEditTests: XCTestCase {
    func testValidationAndJSONPaste() throws {
        let model = BookSourceEditModel()
        XCTAssertThrowsError(try model.validated(existingURLs: [], now: 1))
        try model.applyJSON(#"{"bookSourceUrl":"https://example.invalid","bookSourceName":"测试","ruleContent":{"content":"tag.p@text"}}"#)
        XCTAssertThrowsError(try model.validated(existingURLs: ["https://example.invalid"], now: 1))
        XCTAssertEqual(model.value("ruleContent.content"), "tag.p@text")
        try model.setValue("tag.div@text", for: "ruleContent.content")
        XCTAssertTrue(model.jsonText.contains("tag.div@text"))
        XCTAssertEqual(try model.validated(existingURLs: [], now: 9).lastUpdateTime, 9)
        let previous = model.jsonText
        XCTAssertThrowsError(try model.applyJSON("[]"))
        XCTAssertEqual(model.jsonText, previous)
    }

    func testJSONArrayPasteUsesFirstSource() throws {
        let model = BookSourceEditModel()
        try model.applyJSON(#"[{"bookSourceUrl":"first","bookSourceName":"A"},{"bookSourceUrl":"second"}]"#)
        XCTAssertEqual(model.source.bookSourceUrl, "first")
        XCTAssertEqual(model.source.bookSourceName, "A")
    }

    func testMixedTXTImportReservesExplicitIDs() async throws {
        for text in [#"[{"id":100,"name":"A","rule":"^A$"},{"name":"B","rule":"^B$"}]"#,
                     #"[{"name":"B","rule":"^B$"},{"id":100,"name":"A","rule":"^A$"}]"#] {
            let model = RulesManagementModel(kind: .txt, database: try AppDatabase.inMemory())
            await model.load(); model.jsonText = text
            let success = await model.importJSON(now: 100)
            XCTAssertTrue(success)
            XCTAssertEqual(model.txtRules.filter { $0.id >= 100 }.map(\.name).sorted(), ["A", "B"])
            XCTAssertEqual(model.txtRules.first { $0.id == 100 }?.name, "A")
        }
    }

    func testExploreBulkTogglePreservesNormalEnabledAndOrder() async throws {
        let repository = BookSourceRepository(database: try AppDatabase.inMemory())
        var a = BookSourceRow(); a.bookSourceUrl = "a"; a.enabled = false; a.customOrder = 5
        var b = BookSourceRow(); b.bookSourceUrl = "b"; b.customOrder = 9
        try await repository.upsert([a, b])
        let model = SourcesViewModel(repository: repository, httpClient: ReplayHttpClient())
        await model.load(); model.selectedURLs = ["a"]
        await model.batchExploreEnabled(false)
        XCTAssertEqual(model.sources.map(\.enabledExplore), [false, true])
        XCTAssertEqual(model.sources.map(\.enabled), [false, true])
        XCTAssertEqual(model.sources.map(\.customOrder), [5, 9])
        await model.batchExploreEnabled(true)
        XCTAssertEqual(model.sources.map(\.enabledExplore), [true, true])
        XCTAssertEqual(model.sources.map(\.enabled), [false, true])
    }

    func testSortAndBulkOrder() throws {
        var a = BookSourceRow(); a.bookSourceUrl = "a"; a.bookSourceName = "阿"; a.customOrder = 1
        a.weight = 3; a.lastUpdateTime = 1; a.respondTime = 10
        var b = BookSourceRow(); b.bookSourceUrl = "b"; b.bookSourceName = "波"; b.customOrder = 2
        b.weight = 1; b.lastUpdateTime = 3; b.respondTime = 20
        var c = BookSourceRow(); c.bookSourceUrl = "c"; c.customOrder = 3
        XCTAssertEqual(SourceManagement.sorted([b, a], by: .name).map(\.bookSourceUrl), ["a", "b"])
        XCTAssertEqual(SourceManagement.sorted([a, b], by: .weight).map(\.bookSourceUrl), ["b", "a"])
        XCTAssertEqual(SourceManagement.sorted([a, b], by: .update).map(\.bookSourceUrl), ["b", "a"])
        XCTAssertEqual(SourceManagement.sorted([a, b], by: .respond).map(\.bookSourceUrl), ["a", "b"])
        let disabled = SourceManagement.setEnabled([a, b], selected: ["a"], enabled: false)
        XCTAssertFalse(disabled[0].enabled); XCTAssertTrue(disabled[1].enabled)
        XCTAssertEqual(disabled.map(\.customOrder), [1, 2])
        XCTAssertEqual(SourceManagement.sorted([a, b], by: .weight, ascending: false).map(\.bookSourceUrl), ["a", "b"])
        XCTAssertEqual(SourceManagement.sorted([a, b], by: .update, ascending: false).map(\.bookSourceUrl), ["a", "b"])
        XCTAssertEqual(SourceManagement.sorted([a, b], by: .respond, ascending: false).map(\.bookSourceUrl), ["b", "a"])
        let top = try SourceManagement.move([a, b, c], selected: ["a", "b"], toTop: true)
        XCTAssertEqual(top.map(\.customOrder), [0, -1, 3])
        let bottom = try SourceManagement.move([a, b, c], selected: ["a", "b"], toTop: false)
        XCTAssertEqual(bottom.map(\.customOrder), [4, 5, 3])
        a.customOrder = Int(Int32.min)
        XCTAssertThrowsError(try SourceManagement.move([a], selected: ["a"], toTop: true))
    }

    func testInvalidFieldCannotSaveAndJSONObjectRepairs() throws {
        var source = BookSource(); source.bookSourceUrl = "a"; source.bookSourceName = "A"
        let model = BookSourceEditModel(source: source, isNew: false)
        XCTAssertThrowsError(try model.setValue("bad", for: "weight"))
        XCTAssertEqual(model.value("weight"), "bad")
        XCTAssertThrowsError(try model.validated(existingURLs: ["a"], now: 1))
        try model.setValue("5", for: "weight")
        XCTAssertEqual(try model.validated(existingURLs: ["a"], now: 1).weight, 5)
        XCTAssertEqual(SourceManagement.groups("一，二; 一；三"), ["一", "二", "三"])
        XCTAssertThrowsError(try model.setValue("2147483648", for: "weight"))
    }

    func testEditorPersistenceRejectsDuplicateWithoutDeletingOriginal() async throws {
        let db = try AppDatabase.inMemory()
        let repository = BookSourceRepository(database: db)
        var a = BookSourceRow(); a.bookSourceUrl = "a"; a.bookSourceName = "A"
        var b = BookSourceRow(); b.bookSourceUrl = "b"; b.bookSourceName = "B"
        try await repository.upsert([a, b])
        var source = BookSource(); source.bookSourceUrl = "a"; source.bookSourceName = "A"
        let model = BookSourceEditModel(source: source, isNew: false)
        try model.setValue("b", for: "bookSourceUrl")
        do { try await model.save(repository: repository, jsonMode: false, now: 1); XCTFail("应拒绝重复地址") }
        catch {}
        let before = try await repository.list()
        XCTAssertEqual(before.count, 2)
        try model.setValue("c", for: "bookSourceUrl")
        try await model.save(repository: repository, jsonMode: false, now: 1)
        let after = try await repository.list()
        XCTAssertEqual(Set(after.map(\.bookSourceUrl)), ["b", "c"])
    }

    func testReplaceValidationAndJSONPreservesIdentity() throws {
        var row = ReplaceRuleRow(); row.id = 7
        let model = ReplaceRuleEditModel(rule: row)
        XCTAssertThrowsError(try model.validate())
        model.rule.pattern = "["
        XCTAssertThrowsError(try model.validate())
        model.jsonText = #"{"id":99,"pattern":"a","replacement":"b","order":8}"#
        try model.applyJSON(); try model.validate()
        XCTAssertEqual(model.rule.id, 7); XCTAssertEqual(model.rule.order, 8)
        let entity = try JSONDecoder().decode([ReplaceRule].self, from: Data(ReplaceRuleEditModel.export([model.rule]).utf8))
        XCTAssertEqual(entity.first?.order, 8)
    }

    func testRuleImportDefaultsAndAtomicFailure() async throws {
        let db = try AppDatabase.inMemory()
        let model = RulesManagementModel(kind: .txt, database: db)
        await model.load()
        model.jsonText = #"[{"name":"A","rule":"^A$"},{"name":"B","rule":"^B$"}]"#
        let imported = await model.importJSON(now: 100)
        XCTAssertTrue(imported)
        XCTAssertEqual(model.txtRules.filter { $0.id >= 100 }.map(\.id).sorted(), [100, 101])
        let count = model.txtRules.count
        model.jsonText = #"[{"name":"C","rule":"^C$"},{"name":"坏规则","rule":"["}]"#
        let invalid = await model.importJSON(now: 200)
        XCTAssertFalse(invalid)
        await model.load()
        XCTAssertEqual(model.txtRules.count, count)
        let dict = RulesManagementModel(kind: .dictionary, database: db)
        dict.jsonText = #"{"name":"词典","urlRule":"https://example.invalid"}"#
        let importedDict = await dict.importJSON(now: 1)
        XCTAssertTrue(importedDict)
        XCTAssertTrue(dict.dictRules.contains { $0.name == "词典" && $0.enabled })
    }

    func testManagementBatchPersistsOrderAndGroups() async throws {
        let db = try AppDatabase.inMemory()
        let repository = BookSourceRepository(database: db)
        var a = BookSourceRow(); a.bookSourceUrl = "a"; a.bookSourceName = "A"; a.customOrder = 3
        var b = BookSourceRow(); b.bookSourceUrl = "b"; b.bookSourceName = "B"; b.customOrder = 7
        try await repository.upsert([a, b])
        let model = SourcesViewModel(repository: repository, httpClient: ReplayHttpClient())
        await model.load(); model.selectedURLs = ["a"]
        await model.batchEnabled(false)
        XCTAssertEqual(model.sources.map(\.customOrder), [3, 7])
        XCTAssertEqual(model.sources.map(\.enabled), [false, true])
        await model.changeGroup("一,二", removing: false)
        await model.changeGroup("一", removing: true)
        XCTAssertEqual(model.sources.first?.bookSourceGroup, "二")
        await model.move(selected: ["a"], toTop: false)
        XCTAssertEqual(model.sources.map(\.bookSourceUrl), ["b", "a"])
        let exported = try JSONDecoder().decode([BookSource].self, from: Data(model.exportText(selected: ["a"]).utf8))
        XCTAssertEqual(exported.map(\.bookSourceUrl), ["a"])
    }
}
