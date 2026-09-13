import XCTest
import LegadoCore
@testable import SourceLoginCheck

@MainActor
final class SourceLoginViewModelTests: XCTestCase {
    func testDefaultsSubmitAndError() async throws {
        let login = SourceLogin(database: try .inMemory(), client: ReplayHttpClient())
        var source = BookSource(); source.bookSourceUrl = "https://example.invalid"
        source.loginUi = #"[{"name":"账号","default":"guest"}]"#
        source.loginUrl = "function login(){throw 'denied'}"
        let model = SourceLoginViewModel(source: source, service: login)
        await model.load()
        XCTAssertEqual(model.values["账号"], "guest")
        await model.submit()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isBusy)
        XCTAssertFalse(model.completed)
    }

    func testBatchProgressAndFailures() async throws {
        let db = try AppDatabase.inMemory()
        let model = CheckSourceViewModel(checker: SourceChecker(client: ReplayHttpClient(), database: db))
        var one = BookSource(); one.bookSourceUrl = "https://one.invalid"
        var two = BookSource(); two.bookSourceUrl = "https://two.invalid"
        await model.run(sources: [one, two])
        XCTAssertEqual(model.results.count, 2)
        XCTAssertEqual(model.completedCount, 2)
        XCTAssertFalse(model.isRunning)
        XCTAssertTrue(model.results.allSatisfy { !$0.succeeded })
    }
}
