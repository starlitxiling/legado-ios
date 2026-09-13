import XCTest
@testable import LegadoCore

final class JavaHostNetworkTests: XCTestCase {
    private let url = URL(string: "https://example.test/a")!

    private func engine(_ client: ReplayHttpClient) -> JsEngine {
        JsEngine(httpClient: client, cookieStore: CookieStore(), cacheManager: CacheManager(directory: nil))
    }

    func testAjaxArrayArgumentAndHTTPErrorBody() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        await client.enqueue(url: url, response: HttpResponse(status: 503, body: Data("unavailable".utf8), finalURL: url))
        XCTAssertEqual(try engine.evaluateScript("java.ajax(['https://example.test/a','ignored'])") as? String, "unavailable")
    }

    func testFailureContracts() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        for _ in 0..<4 { await client.enqueue(url: url, error: URLError(.timedOut)) }
        let message = try XCTUnwrap(try engine.evaluateScript("java.ajax('https://example.test/a')") as? String)
        XCTAssertTrue(message.contains("-1001"))
        XCTAssertEqual(try engine.evaluateScript("var r=java.connect('https://example.test/a');r.code()===200 && r.body.includes('-1001')") as? Bool, true)
        XCTAssertThrowsError(try engine.evaluateScript("java.get('https://example.test/a',null)"))
        XCTAssertThrowsError(try engine.evaluateScript("java.ajaxAll(['https://example.test/a'])"))
    }

    func testConnectionMethodsAndRawPostBody() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        await client.enqueue(url: url, method: "POST", response: HttpResponse(status: 302, body: Data("ok".utf8), finalURL: url, headers: ["Location": "/next", "Set-Cookie": "sid=1; Path=/"]))
        XCTAssertEqual(try engine.evaluateScript("var r=java.post('https://example.test/a','a=hello world',new Map([['X-Test','yes']]));[r.body(),r.statusCode(),r.header('location'),r.cookie('sid'),r.url()].join('|')") as? String,
                       "ok|302|/next|1|https://example.test/a")
        let recorded = await client.requests
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(request.body, Data("a=hello world".utf8))
        XCTAssertEqual(request.timeout, 30)
        XCTAssertFalse(request.followRedirects)
        XCTAssertEqual(request.headers["X-Test"], "yes")
        await client.enqueue(url: url, method: "HEAD", response: HttpResponse(status: 404, finalURL: url))
        XCTAssertThrowsError(try engine.evaluateScript("java.head('https://example.test/a','{}')"))
    }

    func testCookieInjectionAndResponseWriteback() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        engine.networkSource = AnalyzeUrlExecutor.Source(key: "source", enabledCookieJar: true)
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("ok".utf8), finalURL: url, headers: ["Set-Cookie": "sid=new; Path=/"]))
        XCTAssertEqual(try engine.evaluateScript("cookie.setCookie('https://example.test','sid=old'); java.ajax('https://example.test/a');java.getCookie('https://example.test','sid')") as? String, "new")
        let requests = await client.requests
        XCTAssertEqual(requests.first?.headers["Cookie"], "sid=old")
        XCTAssertEqual(try engine.evaluateScript("cookie.replaceCookie('https://example.test','x=1');cookie.getKey('https://example.test','x')") as? String, "1")
        XCTAssertEqual(try engine.evaluateScript("cookie.removeCookie('https://example.test');cookie.getCookie('https://example.test')") as? String, "")
    }

    func testAjaxAllPreservesOrderAndPropagatesUnmatchedRequest() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        for i in 0..<8 {
            let target = URL(string: "https://example.test/\(i)")!
            await client.enqueue(url: target, response: HttpResponse(status: 200, body: Data("\(i)".utf8), finalURL: target))
        }
        XCTAssertEqual(try engine.evaluateScript("java.ajaxAll(Array.from({length:8},(_,i)=>'https://example.test/'+i)).map(r=>r.body).join(',')") as? String, "0,1,2,3,4,5,6,7")
        XCTAssertThrowsError(try engine.evaluateScript("java.ajaxAll(['https://example.test/missing'])"))
    }

    func testExecutorScriptsOptionsRetryAndRawPreservation() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        await client.enqueue(url: url, method: "POST", response: HttpResponse(status: 500, finalURL: url))
        await client.enqueue(url: url, method: "POST", response: HttpResponse(status: 200, body: Data("hello".utf8), finalURL: url))
        let rule = #"<js>'https://example.test/'</js>@result{{key}},{"method":"POST","body":"q=a b","retry":1,"bodyJs":"result.toUpperCase()"}"#
        let executor = try AnalyzeUrlExecutor(rule, engine: engine, bindings: ["key": "a"])
        let result = try await executor.getStrResponse()
        XCTAssertEqual(result.body, "HELLO")
        XCTAssertEqual(result.raw.body, Data("hello".utf8))
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.body, Data("q=a+b".utf8))
    }

    func testTypeDownloadAndCacheFile() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data([0, 255]), finalURL: url))
        XCTAssertEqual(try engine.evaluateScript(#"java.ajax('https://example.test/a,{"type":"bin"}')"#) as? String, "00ff")
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("cached".utf8), finalURL: url))
        XCTAssertEqual(try engine.evaluateScript("java.cacheFile('https://example.test/a');java.cacheFile('https://example.test/a')") as? String, "cached")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertThrowsError(try engine.evaluateScript("java.downloadFile('https://example.test/missing')"))
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data([0,255]), finalURL: url))
        let path = try XCTUnwrap(try engine.evaluateScript("java.downloadFile('https://example.test/a')") as? String)
        XCTAssertTrue(path.hasSuffix(".ext"))
        let bytes = try await engine.downloadStore.read(path)
        XCTAssertEqual(bytes, Data([0,255]))
        let hexPath = try XCTUnwrap(try engine.evaluateScript(#"java.downloadFile('0102','https://example.test/a,{"type":"bin"}')"#) as? String)
        let hexBytes = try await engine.downloadStore.read(hexPath)
        XCTAssertEqual(hexBytes, Data([1,2]))
    }

    func testCacheJSConversionsAndDelete() throws {
        let engine = engine(ReplayHttpClient())
        XCTAssertEqual(try engine.evaluateScript("cache.put('n',42);[cache.get('n'),cache.getInt('n'),cache.getLong('n'),cache.getDouble('n'),cache.getFloat('n')].join('|')") as? String, "42|42|42|42|42")
        XCTAssertEqual(try engine.evaluateScript("cache.put('n','2147483648');cache.getInt('n')===null") as? Bool, true)
        XCTAssertEqual(try engine.evaluateScript("cache.delete('n');cache.get('n')===null") as? Bool, true)
        XCTAssertThrowsError(try engine.evaluateScript("cache.put()"))
        XCTAssertThrowsError(try engine.evaluateScript("cookie.getKey('https://example.test')"))
    }

    func testWebViewIsExplicitAndOptionJSRewritesURL() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("yes".utf8), finalURL: url))
        XCTAssertEqual(try engine.evaluateScript(#"java.ajax('https://example.test/old,'+JSON.stringify({js: "result.replace('old','a')"}))"#) as? String, "yes")
        let executor = try AnalyzeUrlExecutor(#"https://example.test/a,{"webView":true}"#, engine: engine)
        do { _ = try await executor.getStrResponse(); XCTFail("应抛出未实现错误") }
        catch { XCTAssertTrue(String(describing: error).contains("webView")) }
    }

    func testConnectNullHeadersRetainsSourceHeadersAndCallTimeout() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        engine.networkSource = .init(key: "source", headers: ["X-Source": "kept"])
        await client.enqueue(url: url, response: HttpResponse(status: 401, body: Data("denied".utf8), finalURL: url))
        XCTAssertEqual(try engine.evaluateScript("java.connect('https://example.test/a',null,1000).body()") as? String, "denied")
        let requests = await client.requests
        XCTAssertEqual(requests.first?.headers["X-Source"], "kept")
        XCTAssertEqual(requests.first?.callTimeout, 1)
        await client.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url))
        _ = try engine.evaluateScript(#"java.connect('https://example.test/a,{"timeout":3000}',null,1000)"#)
        let timed = await client.requests
        XCTAssertEqual(timed.last?.timeout, 3)
        XCTAssertEqual(timed.last?.callTimeout, 1)
    }

    func testNonURLSourceCookieDomainAndOptionCookieMerge() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        engine.networkSource = .init(key: "custom-source")
        await engine.cookieStore.setCookie(url: "custom-source", cookie: "source=1; sid=old")
        await engine.cookieStore.setCookie(url: url.absoluteString, cookie: "wrong=1")
        await client.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url))
        _ = try engine.evaluateScript(#"java.ajax('https://example.test/a,{"headers":{"Cookie":"sid=new"}}')"#)
        let requests = await client.requests
        XCTAssertEqual(requests.first?.headers["Cookie"], "source=1; sid=new")
    }

    func testRawHeadUsesGetAndBytesAvoidDecoding() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        await client.enqueue(url: url, response: HttpResponse(status: 500, body: Data([0,255]), finalURL: url, headers: ["Content-Type":"text/plain; charset=unsupported"]))
        let executor = try AnalyzeUrlExecutor(#"https://example.test/a,{"method":"HEAD","bodyJs":"throw Error('unused')","webView":true}"#, engine: engine)
        let raw = try await executor.getResponse()
        XCTAssertEqual(raw.status, 500)
        XCTAssertEqual(raw.body, Data([0,255]))
    }

    func testInitializationExceptionsAndCancellationPropagate() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        XCTAssertThrowsError(try engine.evaluateScript(#"java.ajax('@js:throw new Error("bad url")')"#))
        await client.enqueue(url: url, error: CancellationError())
        XCTAssertThrowsError(try engine.evaluateScript("java.ajax('https://example.test/a')"))
        await client.enqueue(url: url, error: URLError(.cancelled))
        XCTAssertThrowsError(try engine.evaluateScript("java.connect('https://example.test/a')"))
    }

    func testCookieDisabledAndInvalidRequestHeaders() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        await client.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url, headers: ["Set-Cookie":"sid=ignored; Path=/"]))
        XCTAssertEqual(try engine.evaluateScript("java.ajax('https://example.test/a');cookie.getCookie('https://example.test')") as? String, "")
        XCTAssertThrowsError(try engine.evaluateScript("java.get('https://example.test/a','broken')"))
        XCTAssertThrowsError(try engine.evaluateScript("java.post('https://example.test/a','x',{a:null})"))
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testInvalidCallTimeoutDoesNotSendRequest() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        XCTAssertEqual(try engine.evaluateScript("java.ajax('https://example.test/a',-1).includes('callTimeout')") as? Bool, true)
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testAjaxAllActuallyStartsConcurrentRequests() async throws {
        let client = ReplayHttpClient(), gate = HostReplayGate(client: client)
        let engine = engine(client)
        engine.httpClient = gate
        let second = URL(string: "https://example.test/b")!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("a".utf8), finalURL: url))
        await client.enqueue(url: second, response: HttpResponse(status: 200, body: Data("b".utf8), finalURL: second))
        XCTAssertEqual(try engine.evaluateScript("java.ajaxAll(['https://example.test/a','https://example.test/b']).map(r=>r.body).join('')") as? String, "ab")
        let peak = await gate.peak
        XCTAssertEqual(peak, 2)
    }

    func testAjaxTestAllClassifiesTimeoutAndKeepsHTTPStatus() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        await client.enqueue(url: url, error: URLError(.timedOut))
        await client.enqueue(url: url, response: HttpResponse(status: 500, body: Data("server".utf8), finalURL: url))
        XCTAssertEqual(try engine.evaluateScript("java.ajaxTestAll(['https://example.test/a'],200,true)[0].callTime") as? Double, -2)
        XCTAssertEqual(try engine.evaluateScript("java.ajaxTestAll(['https://example.test/a'],200,true)[0].code()") as? Double, 500)
        let requests = await client.requests
        XCTAssertEqual(requests.first?.callTimeout, 0.2)
    }

    func testDataURIAndXMLDeclarationPrecedence() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        let data = try AnalyzeUrlExecutor(#"data:application/octet-stream;base64,AP8=,{"type":"bin"}"#, engine: engine)
        let binary = try await data.getStrResponse()
        XCTAssertEqual(binary.body, "00ff")
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("<root/>".utf8), finalURL: url, headers: ["Content-Type":"application/xml"]))
        let xml = try AnalyzeUrlExecutor(#"https://example.test/a,{"bodyJs":"throw Error('must not run')"}"#, engine: engine)
        let response = try await xml.getStrResponse()
        XCTAssertEqual(response.body, "<?xml version=\"1.0\"?><root/>")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testResponseScriptCanMakeNestedHostRequest() async throws {
        let client = ReplayHttpClient(), engine = engine(client)
        let second = URL(string: "https://example.test/b")!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("a".utf8), finalURL: url))
        await client.enqueue(url: second, response: HttpResponse(status: 200, body: Data("b".utf8), finalURL: second))
        XCTAssertEqual(try engine.evaluateScript(#"java.ajax('https://example.test/a,'+JSON.stringify({bodyJs:"result+java.ajax('https://example.test/b')"}))"#) as? String, "ab")
    }
}

private actor HostReplayGate: HttpClient {
    let client: ReplayHttpClient
    var waiting: CheckedContinuation<Void, Never>?
    var active = 0
    var peak = 0
    init(client: ReplayHttpClient) { self.client = client }
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        active += 1
        peak = max(peak, active)
        if active == 1 { await withCheckedContinuation { waiting = $0 } }
        else { waiting?.resume(); waiting = nil }
        defer { active -= 1 }
        return try await client.send(request)
    }
}
