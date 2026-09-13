import XCTest
import LegadoCore
@testable import SourceLoginCheck

@MainActor
final class SourceLoginReviewViewModelTests: XCTestCase {
    func testReview06WebLoginUsesFinalURL() async throws {
        let db = try AppDatabase.inMemory()
        let service = SourceLogin(database: db, client: ReplayHttpClient(), cookies: CookieStore())
        var source = BookSource(); source.loginUrl = "https://initial.example.com/login"
        let model = SourceLoginViewModel(source: source, service: service)
        let cookies = [HTTPCookie(properties: [.domain: "auth.other.co.uk", .path: "/", .name: "sid", .value: "final"])!]
        await model.completeWebLogin(cookies: cookies, currentURL: URL(string: "https://auth.other.co.uk/home"))
        let rows = try await CookieRepository(database: db).list()
        XCTAssertEqual(rows.map(\.url), ["other.co.uk"])
        XCTAssertEqual(rows.first?.cookie, "sid=final")
        XCTAssertTrue(model.completed)
    }
    func testReview08ButtonUpdatesFieldsAndRendersAgain() async throws {
        let service = SourceLogin(database: try .inMemory(), client: ReplayHttpClient(), cookies: CookieStore())
        var source = BookSource(); source.bookSourceUrl = "https://example.com"
        source.loginUrl = "function login(){}"
        source.loginUi = #"@js: JSON.stringify([{name:'code',default:source.getVariable() || 'old'}])"#
        let model = SourceLoginViewModel(source: source, service: service)
        await model.load()
        await model.submit(action: "source.setVariable('new'); java.reLoginView(); java.upLoginData({code:'typed'});")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.rows.first?.defaultValue, "new")
        XCTAssertEqual(model.values["code"], "typed")
    }
}
