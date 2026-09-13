import Foundation
import XCTest
import LegadoCore
@testable import AppCoreCheck

final class SourceManagementTests: XCTestCase {
    @MainActor
    func testReplacementDefaultAndZeroIDsRemainDistinct() async throws {
        let repository = ReplaceRuleRepository(database: try .inMemory())
        let model = ReplaceRulesViewModel(repository: repository, httpClient: ReplayHttpClient(), now: { 1000 })
        await model.prepareImport(text: """
        [{"pattern":"one"},{"pattern":"two"},{"id":0,"pattern":"three"},{"id":0,"pattern":"four"}]
        """)
        XCTAssertEqual(model.importPreview?.newCount, 4)
        await model.confirmImport()
        let rows = try await repository.list()
        XCTAssertEqual(Set(rows.map(\.pattern)), ["one", "two", "three", "four"])
        XCTAssertEqual(Set(rows.compactMap(\.id)).count, 4)
    }

    @MainActor
    func testCancelledSourcePreviewNeverWritesAndBOMIsAccepted() async throws {
        let repository = BookSourceRepository(database: try .inMemory())
        let model = SourcesViewModel(repository: repository, httpClient: ReplayHttpClient())
        await model.prepareImport(text: "\u{FEFF}{\"bookSourceUrl\":\"https://book.test\",\"bookSourceName\":null}")
        XCTAssertEqual(model.importPreview?.newCount, 1)
        model.cancelImport()
        await model.confirmImport()
        let rows = try await repository.list()
        XCTAssertTrue(rows.isEmpty)
    }

    @MainActor
    func testOversizedDownloadHasNoPreview() async throws {
        let client = ReplayHttpClient()
        let url = URL(string: "https://fixture.test/large")!
        await client.enqueue(url: url, response: .init(status: 200, finalURL: url,
                                                     headers: ["Content-Length": "16777217"]))
        let model = SourcesViewModel(repository: .init(database: try .inMemory()), httpClient: client)
        await model.prepareImport(url: url.absoluteString)
        XCTAssertNil(model.importPreview)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testSourcePreviewDeduplicatesAndSkipsUnsupported() async throws {
        let repository = BookSourceRepository(database: try .inMemory())
        var existing = BookSourceRow()
        existing.bookSourceUrl = "https://existing.test"
        existing.bookSourceName = "旧名称"
        try await repository.upsert(existing)
        let model = SourcesViewModel(repository: repository, httpClient: ReplayHttpClient())
        await model.prepareImport(text: """
        [{"bookSourceUrl":"https://existing.test","bookSourceName":"新名称"},
         {"bookSourceUrl":"https://new.test","bookSourceName":"重复的旧值"},
         {"bookSourceUrl":"https://new.test","bookSourceName":"最终值","ruleSearch":{"name":"h1"}},
         {"bookSourceUrl":"https://js.test","mainJs":"function main() {}"}]
        """)
        XCTAssertEqual(model.importPreview?.newCount, 1)
        XCTAssertEqual(model.importPreview?.overwriteCount, 1)
        XCTAssertEqual(model.importPreview?.unsupportedCount, 1)
        let before = try await repository.list()
        XCTAssertEqual(before.count, 1)
        await model.confirmImport()
        XCTAssertNil(model.errorMessage)
        let after = try await repository.list()
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after.first { $0.bookSourceUrl == "https://existing.test" }?.bookSourceName, "新名称")
        XCTAssertEqual(after.first { $0.bookSourceUrl == "https://new.test" }?.bookSourceName, "最终值")
        XCTAssertEqual(after.first { $0.bookSourceUrl == "https://new.test" }?.ruleSearch?.contains("h1"), true)
    }

    @MainActor
    func testSourceToggleGroupsSearchSortAndDelete() async throws {
        let repository = BookSourceRepository(database: try .inMemory())
        var first = BookSourceRow()
        first.bookSourceUrl = "https://first.test"
        first.bookSourceName = "Alpha"
        first.bookSourceGroup = " 科幻，精品;英文 "
        first.customOrder = 20
        var second = BookSourceRow()
        second.bookSourceUrl = "https://second.test"
        second.bookSourceGroup = "科幻精选"
        second.customOrder = 1
        try await repository.upsert([first, second])
        let model = SourcesViewModel(repository: repository, httpClient: ReplayHttpClient())
        await model.load()
        XCTAssertEqual(model.filteredSources.map(\.bookSourceUrl), [second.bookSourceUrl, first.bookSourceUrl])
        model.selectedGroup = "科幻"
        XCTAssertEqual(model.filteredSources.map(\.bookSourceUrl), [first.bookSourceUrl])
        model.keyword = "ALPHA"
        XCTAssertEqual(model.filteredSources.count, 1)
        model.keyword = "不存在"
        XCTAssertTrue(model.filteredSources.isEmpty)
        await model.setEnabled(first, enabled: false)
        let saved = try await repository.get(bookSourceUrl: first.bookSourceUrl)
        XCTAssertEqual(saved?.enabled, false)
        await model.delete(first)
        let deleted = try await repository.get(bookSourceUrl: first.bookSourceUrl)
        XCTAssertNil(deleted)
    }

    @MainActor
    func testSourceURLAndInvalidInputClearPreview() async throws {
        let client = ReplayHttpClient()
        let url = URL(string: "https://fixture.test/sources")!
        await client.enqueue(url: url, response: .init(status: 200, body: Data("{\"bookSourceUrl\":\"https://book.test\"}".utf8), finalURL: url))
        let model = SourcesViewModel(repository: .init(database: try .inMemory()), httpClient: client)
        await model.prepareImport(url: url.absoluteString)
        XCTAssertEqual(model.importPreview?.newCount, 1)
        await model.prepareImport(text: "bad JSON")
        XCTAssertNil(model.importPreview)
        XCTAssertNotNil(model.errorMessage)
        await client.enqueue(url: url, response: .init(status: 503, finalURL: url))
        await model.prepareImport(url: url.absoluteString)
        XCTAssertNil(model.importPreview)
        XCTAssertTrue(model.errorMessage?.contains("503") == true)
        await model.prepareImport(url: "file:///tmp/source.json")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
    }

    @MainActor
    func testReplaceRuleURLImportToggleFilterAndDelete() async throws {
        let repository = ReplaceRuleRepository(database: try .inMemory())
        let client = ReplayHttpClient()
        let url = URL(string: "https://fixture.test/rules")!
        let json = """
        [{"id":101,"name":"清理","group":"通用；正文","pattern":"广告","replacement":"","order":2},
         {"id":102,"name":"标题","group":"标题","pattern":"标题","order":1}]
        """
        await client.enqueue(url: url, response: .init(status: 200, body: Data(json.utf8), finalURL: url))
        let model = ReplaceRulesViewModel(repository: repository, httpClient: client, now: { 1000 })
        await model.prepareImport(url: url.absoluteString)
        XCTAssertEqual(model.importPreview?.newCount, 2)
        await model.confirmImport()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.filteredRules.map(\.id), [102, 101])
        model.selectedGroup = "正文"
        XCTAssertEqual(model.filteredRules.map(\.id), [101])
        let row = try XCTUnwrap(model.filteredRules.first)
        await model.setEnabled(row, enabled: false)
        let saved = try await repository.get(id: 101)
        XCTAssertEqual(saved?.isEnabled, false)
        await model.prepareImport(text: "{\"id\":101,\"pattern\":\"改写\"}")
        XCTAssertEqual(model.importPreview?.overwriteCount, 1)
        await model.delete(row)
        let deleted = try await repository.get(id: 101)
        XCTAssertNil(deleted)
    }
}
