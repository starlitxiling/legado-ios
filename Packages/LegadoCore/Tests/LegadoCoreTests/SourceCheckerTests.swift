import XCTest
@testable import LegadoCore

final class SourceCheckerTests: XCTestCase {
    private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/Conformance/fixtures/webbook")
    private let paths = ["/search?key=demo&page=1", "/book/1", "/toc/1", "/toc/2", "/read/1", "/read/1-2", "/read/1-3"]
    private let files = ["search.html", "info.html", "toc1.html", "toc2.html", "content1.html", "content2.html", "content3.html"]

    private func setup(failure: Int? = nil, timeout: Bool = false) async throws -> (BookSource, ReplayHttpClient, AppDatabase) {
        let source = try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: fixtures.appendingPathComponent("source.json")))
        let client = ReplayHttpClient()
        for index in paths.indices {
            let url = URL(string: "https://example.invalid" + paths[index])!
            if index == failure { await client.enqueue(url: url, error: URLError(timeout ? .timedOut : .cannotConnectToHost)) }
            else { await client.enqueue(url: url, response: HttpResponse(status: 200, body: try Data(contentsOf: fixtures.appendingPathComponent(files[index])), finalURL: url)) }
        }
        let db = try AppDatabase.inMemory()
        var row = BookSourceRow(); row.bookSourceUrl = source.bookSourceUrl!; row.bookSourceName = source.bookSourceName!
        try await BookSourceRepository(database: db).upsert(row)
        return (source, client, db)
    }

    func testAllStepsAndPersistedState() async throws {
        let (source, client, db) = try await setup()
        let result = try await SourceChecker(client: client, database: db, clock: { 1 }).check(source: source, keyword: "demo")
        XCTAssertEqual(result.steps.map(\.step), [.search, .detail, .toc, .content])
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.steps.allSatisfy { $0.elapsedMilliseconds == 0 })
        let state = try await SourceChecker(client: client, database: db).lastResult(source: source.bookSourceUrl!)
        XCTAssertEqual(state, result)
        let row = try await BookSourceRepository(database: db).get(bookSourceUrl: source.bookSourceUrl!)
        XCTAssertEqual(row?.respondTime, 0)
    }

    func testFailuresAndTimeoutsStopAtEachStep() async throws {
        for (index, step) in [(0, SourceCheckStep.search), (1, .detail), (2, .toc), (4, .content)] {
            for timeout in [false, true] {
                let (source, client, db) = try await setup(failure: index, timeout: timeout)
                let result = try await SourceChecker(client: client, database: db).check(source: source, keyword: "demo")
                XCTAssertFalse(result.succeeded)
                XCTAssertEqual(result.steps.last?.step, step)
                XCTAssertEqual(result.steps.last?.timedOut, timeout)
                XCTAssertNotNil(result.steps.last?.error)
                let requests = await client.requests
                XCTAssertEqual(requests.count, index + 1)
            }
        }
    }

    func testEmptySearchFails() async throws {
        let (source, _, db) = try await setup()
        let client = ReplayHttpClient(); let url = URL(string: "https://example.invalid/search?key=demo&page=1")!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("<html/>".utf8), finalURL: url))
        let result = try await SourceChecker(client: client, database: db).check(source: source, keyword: "demo")
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.steps.count, 1)
    }
}
