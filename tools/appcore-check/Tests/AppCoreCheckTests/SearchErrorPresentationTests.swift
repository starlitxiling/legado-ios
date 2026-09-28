import XCTest
import LegadoCore
@testable import AppCoreCheck

@MainActor
final class SearchErrorPresentationTests: XCTestCase {
    func testNoSourcesExplainsImportBeforeSearch() async throws {
        let database = try AppDatabase.inMemory()
        let model = SearchViewModel(sources: BookSourceRepository(database: database), client: ReplayHttpClient())
        await model.search("Book")
        XCTAssertFalse(model.isSearching)
        XCTAssertTrue(model.errorMessage?.contains("请先导入书源") == true)
    }

    func testCancelledSourceIsNotListedAsFailure() async throws {
        let database = try AppDatabase.inMemory()
        let sources = BookSourceRepository(database: database)
        var source = BookSourceRow(); source.bookSourceUrl = "https://cancelled.test"; source.searchUrl = "/search"
        try await sources.insert(source)
        let model = SearchViewModel(sources: sources, client: FailedSearchClient(code: .cancelled))
        await model.search("Book")
        XCTAssertEqual(model.failedSources, 0)
        XCTAssertTrue(model.sourceFailures.isEmpty)
        XCTAssertNil(model.userError)
    }

    func testFailureNamesSourceAndUsesChineseTimeout() async throws {
        let database = try AppDatabase.inMemory()
        let sources = BookSourceRepository(database: database)
        var source = BookSourceRow(); source.bookSourceUrl = "https://timeout.test"; source.bookSourceName = "Timeout source"
        source.searchUrl = "https://timeout.test/search"
        try await sources.insert(source)
        let model = SearchViewModel(sources: sources, client: FailedSearchClient(code: .timedOut))
        await model.search("Book")
        XCTAssertEqual(model.failedSources, 1)
        XCTAssertTrue(model.sourceFailures.first?.contains("Timeout source") == true)
        XCTAssertTrue(model.sourceFailures.first?.contains("超时") == true)
    }
}

private struct FailedSearchClient: HttpClient {
    let code: URLError.Code
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        if code == .cancelled { throw CancellationError() }
        throw URLError(code)
    }
}
