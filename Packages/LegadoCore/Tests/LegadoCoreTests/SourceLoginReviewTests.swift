import XCTest
@testable import LegadoCore

final class SourceLoginReviewTests: XCTestCase {
    private func source() -> BookSource {
        var source = BookSource(); source.bookSourceUrl = "https://example.com"; source.bookSourceName = "测试"
        source.searchUrl = "/search"; source.ruleSearch = SearchRule(); source.ruleSearch?.bookList = "class.book"
        return source
    }
    func testReview01GBKResponsePreservesBytes() async throws {
        let login = SourceLogin(database: try .inMemory(), client: ReplayHttpClient(), cookies: CookieStore())
        var source = source(); source.loginCheckJs = "if(result.body() !== '中文') throw 'bad charset'; result"
        let response = HttpResponse(status: 200, body: Data([0xd6,0xd0,0xce,0xc4]), finalURL: URL(string: source.bookSourceUrl!)!, headers: ["Content-Type": "text/html; charset=gbk"])
        let checked = try await login.check(source: source, response: response)
        XCTAssertEqual(checked, response)
        XCTAssertEqual(try StrResponse(raw: checked).body, "中文")
    }
    func testReview02OrdinarySourceBindingsPersist() async throws {
        let db = try AppDatabase.inMemory(); let replay = ReplayHttpClient()
        var source = source()
        source.ruleSearch?.name = "@js: source.setVariable('saved'); source.putLoginInfo('{\"账号\":\"user\"}'); source.getLoginInfoMap().get('账号')"
        source.ruleSearch?.bookUrl = "tag.a@href"
        let url = URL(string: "https://example.com/search")!
        await replay.enqueue(url: url, response: HttpResponse(status: 200, body: Data("<div class='book'><a href='/book'>名字</a></div>".utf8), finalURL: url))
        let result = try await WebBook(source: source, client: SourceLoginHttpClient(database: db, underlying: replay)).search(key: "x")
        XCTAssertEqual(result.first?.name, "user")
        let state = try await SourceStateRepository(database: db).load(source: source.bookSourceUrl!)
        XCTAssertEqual(state["variable"], "saved")
    }
    func testReview03ExplicitHeadersWin() async throws {
        let db = try AppDatabase.inMemory(); let replay = ReplayHttpClient(); let source = source()
        try await SourceStateRepository(database: db).save(source: source.bookSourceUrl!, values: ["loginHeader": #"{"Authorization":"stored"}"#])
        let url = URL(string: "https://example.com/search")!
        await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url))
        _ = try await SourceSessionHttpClient(source: source, database: db, client: replay).send(HttpRequest(url: url, headers: ["authorization": "explicit"]))
        let request = await replay.requests.first
        XCTAssertEqual(request?.headers.first { $0.key.lowercased() == "authorization" }?.value, "explicit")
    }
    func testReview04SameSiteSubdomainGetsLoginHeader() async throws {
        let db = try AppDatabase.inMemory(); let replay = ReplayHttpClient(); let source = source()
        try await SourceStateRepository(database: db).save(source: source.bookSourceUrl!, values: ["loginHeader": #"{"Authorization":"stored"}"#])
        for (host, expected) in [("api.example.com", "stored"), ("example.com.evil.org", nil)] {
            let url = URL(string: "https://" + host + "/search")!
            await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url))
            _ = try await SourceSessionHttpClient(source: source, database: db, client: replay).send(HttpRequest(url: url))
            let request = await replay.requests.last
            XCTAssertEqual(request?.headers["Authorization"], expected)
        }
    }
    func testReview05ResponseCookieDoesNotRollBackDuringCheck() async throws {
        let db = try AppDatabase.inMemory(); let replay = ReplayHttpClient(); var source = source()
        let login = SourceLogin(database: db, client: replay, cookies: CookieStore())
        source.loginUrl = #"function login(){source.putLoginHeader('{"Cookie":"sid=old"}')}"#
        try await login.submit(source: source, values: [:])
        source.loginUrl = nil; source.loginCheckJs = "result"
        let url = URL(string: "https://example.com/search")!
        await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url, headers: ["Set-Cookie": "sid=new; Path=/"]))
        _ = try await SourceSessionHttpClient(source: source, database: db, client: replay).send(HttpRequest(url: url, enabledCookieJar: true))
        let row = try await CookieRepository(database: db).get(url: "example.com")
        XCTAssertEqual(row?.cookie, "sid=new")
    }
    func testReview07CredentialsNeverEnterStateTable() async throws {
        let db = try AppDatabase.inMemory(); let login = SourceLogin(database: db, client: ReplayHttpClient(), cookies: CookieStore())
        var source = source(); source.loginUrl = "function login(){}"
        try await login.submit(source: source, values: ["password": "private-password"])
        let state = try await SourceStateRepository(database: db).load(source: source.bookSourceUrl!)
        XCTAssertNil(state["loginInfo"])
        XCTAssertFalse(state.values.contains { $0.contains("private-password") })
        let stored = try await login.storedValues(source: source)
        XCTAssertEqual(stored["password"], "private-password")
    }
    func testReview08ButtonExtensionsAreBound() async throws {
        let login = SourceLogin(database: try .inMemory(), client: ReplayHttpClient(), cookies: CookieStore())
        var source = source(); source.loginUrl = "function login(){}"
        try await login.submit(source: source, values: ["code": "old"], action: "java.upLoginData({code:'new'}); java.reLoginView(true);")
    }
    func testReview09WholeCheckTimeout() async throws {
        let result = try await SourceChecker(client: ReplayHttpClient(), database: .inMemory()).check(source: source(), timeout: 0)
        XCTAssertTrue(result.steps.last?.timedOut == true)
    }
    func testReview10FailureWritesPenaltyCommentAndGroup() async throws {
        let db = try AppDatabase.inMemory(); let replay = ReplayHttpClient(); let source = source()
        var row = BookSourceRow(); row.bookSourceUrl = source.bookSourceUrl!; row.bookSourceName = "测试"; row.bookSourceGroup = "收藏"; row.bookSourceComment = "作者说明"
        try await BookSourceRepository(database: db).upsert(row)
        let url = URL(string: "https://example.com/search")!
        await replay.enqueue(url: url, error: URLError(.cannotConnectToHost))
        let result = try await SourceChecker(client: replay, database: db, clock: { 1 }).check(source: source, timeout: 2)
        let saved = try await BookSourceRepository(database: db).get(bookSourceUrl: source.bookSourceUrl!)
        XCTAssertEqual(saved?.respondTime, 2000 + result.elapsedMilliseconds)
        XCTAssertTrue(saved?.bookSourceGroup?.contains("网站失效") == true)
        XCTAssertTrue(saved?.bookSourceGroup?.contains("收藏") == true)
        XCTAssertTrue(saved?.bookSourceComment?.contains("// Error: ") == true)
        XCTAssertTrue(saved?.bookSourceComment?.contains("作者说明") == true)
    }

    func testReview03URLHeadersOverrideLoginWhichOverridesSourceHeaders() async throws {
        let db = try AppDatabase.inMemory(); let replay = ReplayHttpClient(); var source = source()
        source.header = #"{"Authorization":"source","X-Explicit":"source"}"#
        source.searchUrl = #"/search,{"headers":{"X-Explicit":"url"}}"#
        try await SourceStateRepository(database: db).save(source: source.bookSourceUrl!, values: ["loginHeader": #"{"Authorization":"login","X-Explicit":"login"}"#])
        let url = URL(string: "https://example.com/search")!
        await replay.enqueue(url: url, response: HttpResponse(status: 200, body: Data("<html/>".utf8), finalURL: url))
        _ = try await WebBook(source: source, client: SourceLoginHttpClient(database: db, underlying: replay)).search(key: "x")
        let request = await replay.requests.first
        XCTAssertEqual(request?.headers["Authorization"], "login")
        XCTAssertEqual(request?.headers["X-Explicit"], "url")
    }

    func testReview01CookedGBKResponseDoesNotDecodeTwice() async throws {
        let db = try AppDatabase.inMemory(); let replay = ReplayHttpClient(); var source = source()
        source.ruleSearch?.name = "tag.a@text"; source.ruleSearch?.bookUrl = "tag.a@href"
        source.loginCheckJs = "({body:function(){return result.body().replace('中文','更新')},code:function(){return result.code()},url:function(){return result.url()}})"
        let url = URL(string: "https://example.com/search")!
        let bytes = "<div class='book'><a href='/book'>中文</a></div>".data(using: try ResponseDecoder.encoding(for: "gbk"))!
        await replay.enqueue(url: url, response: HttpResponse(status: 200, body: bytes, finalURL: url, headers: ["Content-Type": "text/html; charset=gbk"]))
        let books = try await WebBook(source: source, client: SourceLoginHttpClient(database: db, underlying: replay)).search(key: "x")
        XCTAssertEqual(books.first?.name, "更新")
    }

    func testReview05CheckSeesServerCookieAndKeepsIt() async throws {
        let db = try AppDatabase.inMemory(); let replay = ReplayHttpClient(); var source = source()
        try await SourceStateRepository(database: db).save(source: source.bookSourceUrl!, values: ["loginHeader": #"{"Cookie":"sid=old"}"#])
        source.loginCheckJs = "if(cookie.getKey(source.getKey(),'sid')!=='new')throw 'stale cookie';result"
        let url = URL(string: "https://example.com/search")!
        await replay.enqueue(url: url, response: HttpResponse(status: 200, body: Data("<html/>".utf8), finalURL: url, headers: ["Set-Cookie": "sid=new; Path=/"]))
        _ = try await WebBook(source: source, client: SourceLoginHttpClient(database: db, underlying: replay)).search(key: "x")
        let row = try await CookieRepository(database: db).get(url: "example.com")
        XCTAssertEqual(row?.cookie, "sid=new")
    }

    func testReview07LegacyInfoMovesToSecretStore() async throws {
        let db = try AppDatabase.inMemory(); let source = source(); let secrets = MemorySourceSecretStore()
        try await SourceStateRepository(database: db).save(source: source.bookSourceUrl!, values: ["loginInfo": #"{"password":"legacy"}"#])
        let login = SourceLogin(database: db, client: ReplayHttpClient(), secrets: secrets)
        let stored = try await login.storedValues(source: source)
        XCTAssertEqual(stored["password"], "legacy")
        let state = try await SourceStateRepository(database: db).load(source: source.bookSourceUrl!)
        XCTAssertNil(state["loginInfo"])
        let reopened = SourceLogin(database: db, client: ReplayHttpClient(), secrets: secrets)
        let values = try await reopened.storedValues(source: source)
        XCTAssertEqual(values["password"], "legacy")
    }

    func testReview09DeadlineCancelsInflightRequest() async throws {
        let client = ReviewPendingClient(); let db = try AppDatabase.inMemory()
        let checker = SourceChecker(client: client, database: db, clock: { 1 }, sleep: { _ in await client.waitForRequest() })
        let result = try await checker.check(source: source(), timeout: 2)
        XCTAssertTrue(result.steps.last?.timedOut == true)
        let cancelled = await client.cancelled
        XCTAssertTrue(cancelled)
    }

    func testReview09UserCancellationDoesNotWriteFailure() async throws {
        let client = ReviewPendingClient(); let db = try AppDatabase.inMemory(); let source = source()
        let checker = SourceChecker(client: client, database: db, clock: { 1 }, sleep: { _ in try await Task.sleep(nanoseconds: UInt64.max) })
        let task = Task { try await checker.check(source: source) }
        await client.waitForRequest(); task.cancel()
        do { _ = try await task.value; XCTFail("取消必须传播") } catch { XCTAssertTrue(error is CancellationError) }
        let result = try await checker.lastResult(source: source.bookSourceUrl!)
        XCTAssertNil(result)
    }
}

private actor ReviewPendingClient: HttpClient {
    private var started = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var cancelled = false
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        started = true; waiting.forEach { $0.resume() }; waiting = []
        do { try await Task.sleep(nanoseconds: UInt64.max); throw URLError(.unknown) }
        catch { cancelled = error is CancellationError; throw error }
    }
    func waitForRequest() async {
        if started { return }
        await withCheckedContinuation { waiting.append($0) }
    }
}
