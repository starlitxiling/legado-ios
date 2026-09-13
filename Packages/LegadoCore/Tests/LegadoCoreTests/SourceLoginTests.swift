import XCTest
@testable import LegadoCore

final class SourceLoginTests: XCTestCase {
    func testRowsDefaultsAndInvalidJSON() throws {
        let rows = try SourceLogin.parseUI(#"[{"name":"账号","default":"guest"},{"name":"密码","type":"password"},{"name":"登录","type":"button","action":"login()"}]"#)
        XCTAssertEqual(rows.map(\.type), ["text", "password", "button"])
        XCTAssertEqual(rows[0].defaultValue, "guest")
        XCTAssertThrowsError(try SourceLogin.parseUI("invalid"))
        XCTAssertThrowsError(try SourceLogin.parseUI(#"[{"name":"x","type":"unknown"}]"#))
    }

    func testSubmitPersistsInfoVariableAndHeader() async throws {
        let db = try AppDatabase.inMemory()
        let login = SourceLogin(database: db, client: ReplayHttpClient(), cookies: CookieStore())
        var source = BookSource(); source.bookSourceUrl = "https://example.invalid"
        source.loginUrl = #"@js:function login(){source.setVariable(source.getLoginInfoMap().get('账号'));source.putLoginHeader('{"Cookie":"sid=123"}');}"#
        try await login.submit(source: source, values: ["账号": "reader"])
        let state = try await SourceStateRepository(database: db).load(source: source.bookSourceUrl!)
        XCTAssertEqual(state["variable"], "reader")
        XCTAssertNil(state["loginInfo"])
        let stored = try await login.storedValues(source: source)
        XCTAssertEqual(stored["账号"], "reader")
        let cookies = try await CookieRepository(database: db).list()
        XCTAssertEqual(cookies.first?.cookie, "sid=123")
    }

    func testCheckAcceptsResponseAndRejectsFalse() async throws {
        let login = SourceLogin(database: try .inMemory(), client: ReplayHttpClient(), cookies: CookieStore())
        var source = BookSource(); source.bookSourceUrl = "https://example.invalid"
        let response = HttpResponse(status: 200, body: Data("ok".utf8), finalURL: URL(string: source.bookSourceUrl!)!)
        source.loginCheckJs = "if(result.body() != 'ok') throw 'login'; result"
        let checked = try await login.check(source: source, response: response)
        XCTAssertEqual(checked, response)
        source.loginCheckJs = "false"
        do { _ = try await login.check(source: source, response: response); XCTFail("应拒绝") }
        catch { XCTAssertTrue(error is SourceLoginError) }
    }

    func testWebCookiesFilterDomainPersistAndClear() async throws {
        let db = try AppDatabase.inMemory(); let store = CookieStore()
        let login = SourceLogin(database: db, client: ReplayHttpClient(), cookies: store)
        let cookies = [HTTPCookie(properties: [.domain: ".example.invalid", .path: "/", .name: "sid", .value: "ok"])!,
                       HTTPCookie(properties: [.domain: "other.invalid", .path: "/", .name: "bad", .value: "no"])!]
        try await login.saveWebCookies(cookies, url: URL(string: "https://auth.example.invalid/login")!)
        let value = await store.getCookie(url: "https://example.invalid")
        XCTAssertEqual(value, "sid=ok")
        try await login.clearCookies(domain: "example.invalid")
        let rows = try await CookieRepository(database: db).list()
        XCTAssertTrue(rows.isEmpty)
        let cleared = await store.getCookie(url: "https://example.invalid")
        XCTAssertEqual(cleared, "")
    }

    func testSessionClientUsesPersistedCookieAndLoginHeader() async throws {
        let db = try AppDatabase.inMemory(); let replay = ReplayHttpClient()
        let url = URL(string: "https://example.invalid/search")!
        var source = BookSource(); source.bookSourceUrl = "https://example.invalid"
        source.searchUrl = "/search"; source.ruleSearch = SearchRule(); source.ruleSearch?.bookList = "class.book"
        let login = SourceLogin(database: db, client: replay, cookies: CookieStore())
        source.loginUrl = #"function login(){source.putLoginHeader('{"Authorization":"Bearer token","Cookie":"sid=ok"}')}"#
        try await login.submit(source: source, values: [:])
        await replay.enqueue(url: url, response: HttpResponse(status: 200, body: Data("<html/>".utf8), finalURL: url))
        _ = try await WebBook(source: source, client: SourceLoginHttpClient(database: db, underlying: replay)).search(key: "x")
        let request = await replay.requests.first
        XCTAssertEqual(request?.headers["Cookie"], "sid=ok")
        XCTAssertEqual(request?.headers["Authorization"], "Bearer token")
        try await login.clearCookies(domain: "example.invalid")
        await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url))
        _ = try await SourceSessionHttpClient(source: source, database: db, client: replay, timeout: 2).send(HttpRequest(url: url, enabledCookieJar: true))
        let cleared = await replay.requests.last
        XCTAssertNil(cleared?.headers["Cookie"])
        XCTAssertEqual(cleared?.timeout, 2)
    }

    func testDynamicRowsAndJavaAlias() async throws {
        let login = SourceLogin(database: try .inMemory(), client: ReplayHttpClient(), cookies: CookieStore())
        var source = BookSource(); source.bookSourceUrl = "https://example.invalid"
        source.loginUrl = "function login(){java.putVariable(result.get('账号'));}"
        source.loginUi = #"@js: JSON.stringify([{name:'账号',default:'reader'}])"#
        let rows = try await login.rows(source: source)
        XCTAssertEqual(rows.first?.defaultValue, "reader")
        try await login.submit(source: source, values: ["账号": "reader"])
    }

    func testCheckCanCallLoginAndImmediatelyReadCookie() async throws {
        let login = SourceLogin(database: try .inMemory(), client: ReplayHttpClient(), cookies: CookieStore())
        var source = BookSource(); source.bookSourceUrl = "https://example.invalid"
        source.loginUrl = #"function login(){source.putLoginHeader('{"Cookie":"sid=new"}'); if(cookie.getKey(baseUrl,'sid') !== 'new') throw 'cookie missing';}"#
        source.loginCheckJs = "source.login(); result"
        let response = HttpResponse(status: 200, finalURL: URL(string: source.bookSourceUrl!)!)
        let value = try await login.check(source: source, response: response)
        XCTAssertEqual(value, response)
    }
}
