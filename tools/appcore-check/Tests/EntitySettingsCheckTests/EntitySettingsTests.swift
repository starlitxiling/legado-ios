import XCTest
import LegadoCore
@testable import EntitySettingsCheck
@testable import AppCoreCheck

@MainActor
final class EntitySettingsTests: XCTestCase {
    func testServerCreateEditDeleteAndValidation() async throws {
        let database = try AppDatabase.inMemory()
        let model = SubscriptionSettingsModel(database: database, client: EmptyClient(), now: { 10 })
        var server = Server()
        let invalid = await model.save(server)
        XCTAssertFalse(invalid)
        server.name = "server"
        try server.setWebDavConfig(.init(url: "https://example.test/dav", username: "user", password: "synthetic"))
        let saved = await model.save(server)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.servers.count, 1)
        XCTAssertEqual(model.servers[0].id, 10)
        server = model.servers[0]
        server.name = "edited"
        let edited = await model.save(server)
        XCTAssertTrue(edited)
        XCTAssertEqual(model.servers[0].name, "edited")
        XCTAssertEqual(try model.servers[0].webDavConfig()?.username, "user")
        await model.delete(server)
        XCTAssertTrue(model.servers.isEmpty)
    }

    func testSubscriptionDuplicateAndURLImport() async throws {
        let database = try AppDatabase.inMemory()
        let client = EmptyClient(body: #"[{"id":9,"name":"imported","url":"https://example.test/rules","type":1}]"#)
        let model = SubscriptionSettingsModel(database: database, client: client, now: { 10 })
        await model.importText("https://example.test/subscriptions")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.subscriptions.count, 1)
        var duplicate = model.subscriptions[0]; duplicate.id = 0
        let saved = await model.save(duplicate)
        XCTAssertFalse(saved)
        XCTAssertEqual(model.subscriptions.count, 1)
        await model.delete(model.subscriptions[0])
        XCTAssertTrue(model.subscriptions.isEmpty)
    }

    func testSearchRecordsAndClearsHistory() async throws {
        let database = try AppDatabase.inMemory()
        let model = SearchViewModel(sources: BookSourceRepository(database: database), client: EmptyClient(),
                                    keywords: SearchKeywordRepository(database: database), now: { 100 })
        await model.search("  书名  ")
        await model.search("书名")
        XCTAssertEqual(model.history.first?.word, "书名")
        XCTAssertEqual(model.history.first?.usage, 2)
        XCTAssertEqual(model.history.first?.lastUseTime, 100)
        await model.search("  ")
        XCTAssertEqual(model.history.count, 1)
        await model.clearHistory()
        XCTAssertTrue(model.history.isEmpty)
        let stored = try await SearchKeywordRepository(database: database).all()
        XCTAssertTrue(stored.isEmpty)
    }
}

private struct EmptyClient: HttpClient {
    var body = "[]"
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        HttpResponse(status: 200, body: Data(body.utf8), finalURL: request.url)
    }
}

extension EntitySettingsTests {
    func testReviewImportThreeMissingAndCollidingIDs() async throws {
        let db = try AppDatabase.inMemory()
        let model = SubscriptionSettingsModel(database: db, client: EmptyClient(), now: { 10 })
        await model.importText(#"[{"name":"a","url":"https://example.test/a"},{"name":"b","url":"https://example.test/b"},{"name":"c","url":"https://example.test/c"}]"#)
        XCTAssertEqual(model.subscriptions.count, 3)
        await model.importText(#"[{"id":10,"name":"d","url":"https://example.test/d"},{"id":0,"name":"e","url":"https://example.test/e"}]"#)
        XCTAssertEqual(model.subscriptions.count, 5)
    }

    func testReviewRejectTypeThree() async throws {
        let model = SubscriptionSettingsModel(database: try AppDatabase.inMemory(), client: EmptyClient())
        var rule = RuleSub(); rule.name = "invalid"; rule.url = "https://example.test"; rule.type = 3
        let saved = await model.save(rule)
        XCTAssertFalse(saved)
    }
}
