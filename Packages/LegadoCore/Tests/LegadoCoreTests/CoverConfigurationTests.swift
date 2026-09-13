import XCTest
@testable import LegadoCore

final class CoverConfigurationTests: XCTestCase {
    func testCoverEncodingHelpers() throws {
        let engine = JsEngine()
        XCTAssertEqual(try engine.evaluateScript("java.base64Encode('测试')") as? String, "5rWL6K+V")
        XCTAssertEqual(try engine.evaluateScript("java.base64Encode('??', 11)") as? String, "Pz8")
        XCTAssertEqual(try engine.evaluateScript("java.hexDecodeToString('e6b58be8af95')") as? String, "测试")
        XCTAssertThrowsError(try engine.evaluateScript("java.hexDecodeToString('xx')"))
    }
    func testAndroidBuiltInRuleWithFakeResponses() async throws {
        var book = Book(now: 0); book.name = "测试"; book.author = "作者"
        let result = try await CoverSearchRule.androidDefault.search(book: book, client: BuiltInCoverFixtureClient())
        XCTAssertEqual(result, "https://example.test/default.jpg")
    }
    func testRuleUsesBookSearchKeyAndRedirectBase() async throws {
        let rule = CoverSearchRule(enable: true, searchUrl: "https://example.test/?q={{key}}", coverRule: "img@src")
        var book = Book(now: 0); book.name = "测试"; book.author = "作者"
        let value = try await rule.search(book: book, client: CoverFixtureClient())
        XCTAssertEqual(value, "https://redirect.test/cover.png")
        var disabled = rule; disabled.enable = false
        let absent = try await disabled.search(book: book, client: CoverFixtureClient())
        XCTAssertNil(absent)
    }

    func testWifiGateRejectsNetworkButAllowsInjectedWifi() async throws {
        let request = HttpRequest(url: URL(string: "https://example.test/")!)
        do {
            _ = try await CoverNetworkClient(underlying: CoverFixtureClient(), allowed: false).send(request)
            XCTFail("移动网络应禁止下载")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        let response = try await CoverNetworkClient(underlying: CoverFixtureClient(), allowed: true).send(request)
        XCTAssertEqual(response.status, 200)
    }
}

private struct BuiltInCoverFixtureClient: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        let body = request.url.host == "pre-api.tuishujun.com"
            ? "{\"data\":{\"data\":[{\"title\":\"测试\",\"author_nickname\":\"作者\",\"cover\":\"https://example.test/default.jpg\"}]}}"
            : "{\"data\":{\"data\":[]}}"
        return HttpResponse(status: 200, body: Data(body.utf8), finalURL: request.url)
    }
}

private struct CoverFixtureClient: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        HttpResponse(status: 200, body: Data("<img src='/cover.png'>".utf8), finalURL: URL(string: "https://redirect.test/page")!)
    }
}
