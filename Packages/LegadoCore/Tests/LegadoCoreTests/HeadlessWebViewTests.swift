import XCTest
@testable import LegadoCore

final class HeadlessWebViewTests: XCTestCase {
    func testBrowserDefaultRefetchUsesNewPersistentCookie() async throws {
        actor Browser: WebViewUserInteraction {
            func getVerificationCode(_ request: HeadlessWebViewRequest) -> String { "" }
            func startBrowser(_ request: HeadlessWebViewRequest, title: String) {}
            func startBrowserAwait(_ request: HeadlessWebViewRequest, title: String) async -> StrResponse {
                await request.cookieStore?.replaceCookie(url: request.url!, cookie: "sid=new")
                return StrResponse(raw: HttpResponse(status: 200, finalURL: URL(string: request.url!)!), body: "browser")
            }
        }
        let database = try AppDatabase.inMemory(), replay = ReplayHttpClient()
        let url = URL(string: "https://cookie.test/page")!
        var source = BookSource(); source.bookSourceUrl = "https://cookie.test"; source.enabledCookieJar = true
        var row = CookieRow(); row.url = CookieStore.hostKey(url.absoluteString); row.cookie = "sid=old; keep=yes"
        try await CookieRepository(database: database).upsert(row)
        await replay.enqueue(url: url, response: HttpResponse(status: 200, body: Data("refetched".utf8), finalURL: url))
        let client = SourceSessionHttpClient(source: source, database: database, client: replay)
        let result = try await Task.detached {
            let engine = JsEngine(httpClient: client, networkSource: .init(key: source.bookSourceUrl, enabledCookieJar: true), webViewInteraction: Browser())
            return try engine.evaluateScript("java.startBrowserAwait('https://cookie.test/page', '验证').body()") as? String
        }.value
        XCTAssertEqual(result, "refetched")
        let requests = await replay.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(CookieStore.cookieToMap(requests[0].headers["Cookie"] ?? "")["sid"], "new")
        let saved = try await CookieRepository(database: database).get(url: row.url)
        XCTAssertEqual(CookieStore.cookieToMap(saved?.cookie ?? "")["sid"], "new")
        XCTAssertEqual(CookieStore.cookieToMap(saved?.cookie ?? "")["keep"], "yes")
    }

    func testWebViewUserAgentHostUsesInjectedProvider() async throws {
        let result = try await Task.detached {
            let engine = JsEngine()
            engine.webViewUserAgent = { "WK-test-UA" }
            return try engine.evaluateScript("java.getWebViewUA()") as? String
        }.value
        XCTAssertEqual(result, "WK-test-UA")
    }

    actor Fake: HeadlessWebViewProtocol {
        var requests: [HeadlessWebViewRequest] = []
        var active = 0
        var maximum = 0
        let suspend: Bool
        init(suspend: Bool = false) { self.suspend = suspend }
        func load(_ request: HeadlessWebViewRequest) async throws -> StrResponse {
            requests.append(request)
            active += 1
            maximum = max(maximum, active)
            defer { active -= 1 }
            if suspend { try await Task.sleep(nanoseconds: 60_000_000_000) }
            await Task.yield()
            return StrResponse(raw: HttpResponse(status: 200, finalURL: URL(string: request.url!)!), body: "rendered")
        }
    }

    func testForegroundDeniesLoading() async throws {
        let fake = Fake()
        let scheduler = HeadlessWebViewScheduler(loader: fake, isForeground: { false })
        do { _ = try await scheduler.load(.init(url: "https://example.com")); XCTFail("后台必须拒绝") }
        catch { XCTAssertEqual(error as? HeadlessWebViewError, .notForeground) }
        let requests = await fake.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testForegroundRecheckedAfterAdmission() async throws {
        actor Foreground {
            var calls = 0
            func check() -> Bool { calls += 1; return calls == 1 }
        }
        let fake = Fake(), foreground = Foreground()
        let scheduler = HeadlessWebViewScheduler(loader: fake, isForeground: { await foreground.check() })
        do { _ = try await scheduler.load(.init(url: "https://example.com")); XCTFail("入队后退后台必须拒绝") }
        catch { XCTAssertEqual(error as? HeadlessWebViewError, .notForeground) }
        let calls = await foreground.calls
        let requests = await fake.requests
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(requests.isEmpty)
    }

    func testCancellationReleasesQueuedRequest() async throws {
        let fake = Fake(suspend: true)
        let scheduler = HeadlessWebViewScheduler(loader: fake, maximumConcurrentLoads: 1, isForeground: { true })
        let first = Task { try await scheduler.load(.init(url: "https://example.com/first")) }
        while await fake.active == 0 { await Task.yield() }
        let second = Task { try await scheduler.load(.init(url: "https://example.com/second")) }
        second.cancel()
        do { _ = try await second.value; XCTFail("取消必须传播") } catch { XCTAssertTrue(error is CancellationError) }
        first.cancel()
        do { _ = try await first.value; XCTFail("取消必须传播") } catch { XCTAssertTrue(error is CancellationError) }
        let active = await fake.active
        let requests = await fake.requests
        XCTAssertEqual(active, 0)
        XCTAssertEqual(requests.count, 1)
    }

    func testConcurrencyLimit() async throws {
        let fake = Fake()
        let scheduler = HeadlessWebViewScheduler(loader: fake, maximumConcurrentLoads: 1, isForeground: { true })
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 { group.addTask { _ = try await scheduler.load(.init(url: "https://example.com")) } }
            try await group.waitForAll()
        }
        let maximum = await fake.maximum
        let count = await fake.requests.count
        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(count, 12)
    }

    func testTimeoutCancelsAndReleasesSlot() async throws {
        let fake = Fake(suspend: true)
        let scheduler = HeadlessWebViewScheduler(loader: fake, isForeground: { true }, sleep: { _ in
            while await fake.active == 0 { await Task.yield() }
        })
        do { _ = try await scheduler.load(.init(url: "https://example.com")); XCTFail("必须超时") }
        catch { XCTAssertEqual(error as? HeadlessWebViewError, .timedOut) }
        let active = await fake.active
        XCTAssertEqual(active, 0)
    }

    func testAnalyzeUrlPassesWebOptions() async throws {
        let fake = Fake()
        let engine = JsEngine(headlessWebView: fake)
        let executor = try AnalyzeUrlExecutor(#"https://example.com,{"webView":true,"webJs":"document.title","webViewDelayTime":42}"#, engine: engine)
        let result = try await executor.getStrResponse(sourceRegex: ".*mp4")
        XCTAssertEqual(result.body, "rendered")
        let requests = await fake.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.javaScript, "document.title")
        XCTAssertEqual(request.delayTime, 42)
        XCTAssertEqual(request.sourceRegex, ".*mp4")
    }

    func testWebJsAndJavaWebView() async throws {
        let fake = Fake()
        let result = try await Task.detached {
            let engine = JsEngine(baseUrl: "https://example.com", headlessWebView: fake)
            let parser = AnalyzeRule(content: "<p>original</p>", engines: [.js: engine])
            XCTAssertEqual(try parser.getString("@webjs:document.title"), "rendered")
            return try engine.evaluateScript("java.webView(null, 'https://example.com', 'document.title')") as? String
        }.value
        XCTAssertEqual(result, "rendered")
        let requests = await fake.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.html, "<p>original</p>")
        XCTAssertEqual(requests.first?.timeout, 10)
    }

    func testJavaSnifferArguments() async throws {
        let fake = Fake()
        try await Task.detached {
            let engine = JsEngine(headlessWebView: fake)
            XCTAssertEqual(try engine.evaluateScript("java.webViewGetSource(null, 'https://example.com', null, '.*mp4', true, 25)") as? String, "rendered")
            XCTAssertEqual(try engine.evaluateScript("java.webViewGetOverrideUrl(null, 'https://example.com', null, '.*next', false, 50)") as? String, "rendered")
        }.value
        let requests = await fake.requests
        XCTAssertEqual(requests[0].sourceRegex, ".*mp4")
        XCTAssertTrue(requests[0].cacheFirst)
        XCTAssertEqual(requests[0].delayTime, 25)
        XCTAssertEqual(requests[1].overrideUrlRegex, ".*next")
        XCTAssertEqual(requests[1].delayTime, 50)
    }

    func testPostLoadsHTTPResponseHTML() async throws {
        let fake = Fake(), client = ReplayHttpClient(), url = URL(string: "https://example.com")!
        await client.enqueue(url: url, method: "POST", response: HttpResponse(status: 200, body: Data("<p>posted</p>".utf8), finalURL: url))
        let engine = JsEngine(httpClient: client, headlessWebView: fake)
        let executor = try AnalyzeUrlExecutor(#"https://example.com,{"method":"POST","body":"a=1","webView":true}"#, engine: engine)
        let response = try await executor.getStrResponse()
        XCTAssertEqual(response.body, "rendered")
        let requests = await fake.requests
        XCTAssertEqual(requests.first?.html, "<p>posted</p>")
    }

    func testInteractionHostResponses() async throws {
        actor Interaction: WebViewUserInteraction {
            var opened = 0
            func getVerificationCode(_ request: HeadlessWebViewRequest) -> String { "AB12" }
            func startBrowser(_ request: HeadlessWebViewRequest, title: String) { opened += 1 }
            func startBrowserAwait(_ request: HeadlessWebViewRequest, title: String) -> StrResponse {
                StrResponse(raw: HttpResponse(status: 200, finalURL: URL(string: request.url!)!), body: "verified")
            }
        }
        let interaction = Interaction()
        try await Task.detached {
            let engine = JsEngine(webViewInteraction: interaction)
            XCTAssertEqual(try engine.evaluateScript("java.getVerificationCode('https://example.com')") as? String, "AB12")
            _ = try engine.evaluateScript("java.startBrowser('https://example.com', '验证')")
            XCTAssertEqual(try engine.evaluateScript("java.startBrowserAwait('https://example.com', '验证', false).body()") as? String, "verified")
        }.value
        let opened = await interaction.opened
        XCTAssertEqual(opened, 1)
    }
}
