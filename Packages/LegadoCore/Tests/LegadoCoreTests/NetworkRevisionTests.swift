import XCTest
@testable import LegadoCore

final class NetworkRevisionTests: XCTestCase {
    func testRegistrableDomainKeys() async {
        let store = CookieStore()
        await store.setCookie(url: "https://www.example.com/login", cookie: "sid=1")
        let value = await store.getCookie(url: "https://api.example.com/account")
        XCTAssertEqual(value, "sid=1")
        await store.removeCookie(url: "https://api.example.com/")
        let removed = await store.getCookie(url: "https://www.example.com/")
        XCTAssertEqual(removed, "")
        for (url, expected) in [
            ("https://www.biquge.com.cn/", "biquge.com.cn"),
            ("https://a.b.ck/", "a.b.ck"),
            ("https://a.www.ck/", "www.ck"),
            ("https://a.city.kawasaki.jp/", "city.kawasaki.jp"),
            ("https://a.b.unknown/", "b.unknown"),
            ("https://com.cn/", "com.cn"),
            ("https://127.0.0.1:80/a", "127.0.0.1"),
            ("https://[2001:db8::1]/", "[2001:db8::1]"),
            ("example.com", "example.com"),
            ("ftp://www.example.com/", "ftp://www.example.com/"),
            ("not a url", "not a url")
        ] { XCTAssertEqual(CookieStore.hostKey(url), expected, url) }
    }

    func testUserAgentSentinel() throws {
        let url = "https://example.com/"
        XCTAssertEqual(try UrlRequestBuilder.build(url: url).headers["User-Agent"], UrlRequestBuilder.defaultUserAgent)
        let explicit = try UrlRequestBuilder.build(url: url, options: .fromJSON(#"{"headers":{"User-Agent":"custom"}}"#))
        XCTAssertEqual(explicit.headers["User-Agent"], "custom")
        let deleted = try UrlRequestBuilder.build(url: url, options: .fromJSON(#"{"headers":{"User-Agent":"null","X-Value":"null"}}"#))
        XCTAssertNil(deleted.headers.httpHeader("User-Agent"))
        XCTAssertEqual(deleted.headers["X-Value"], "null")
    }

    func testMetaSemicolonCharset() throws {
        let data = Data("<head><meta http-equiv='content-type' content='text/html;gbk'></head>".utf8) + Data([0xD6, 0xD0, 0xCE, 0xC4])
        XCTAssertTrue(try ResponseDecoder.decode(data).hasSuffix("中文"))
    }

    func testReplayRecordsCompleteRequest() async throws {
        let client = ReplayHttpClient()
        let url = URL(string: "https://example.com/post")!
        let request = HttpRequest(url: url, method: "POST", headers: ["X-Test":"record", "Cookie":"a=b"], body: Data([0, 1, 255]), timeout: 7, callTimeout: 12, followRedirects: false)
        await client.enqueue(url: url, method: "POST", response: HttpResponse(status: 200, finalURL: url))
        _ = try await client.send(request)
        let recorded = await client.requests
        XCTAssertEqual(recorded, [request])
        XCTAssertEqual(recorded.first?.headers, request.headers)
        XCTAssertEqual(recorded.first?.body, request.body)
    }

    func testCookieJarStages() async throws {
        let url = URL(string: "https://www.example.com/")!
        for enabled in [false, true] {
            let store = CookieStore()
            await store.setCookie(url: url.absoluteString, cookie: "a=store")
            let client = ReplayHttpClient()
            await client.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url, headers: ["Set-Cookie":"sid=1; Path=/"]))
            _ = try await UrlRequestBuilder.execute(url: url.absoluteString,
                options: .fromJSON(#"{"headers":{"Cookie":"a=header"}}"#),
                cookieStore: store, enabledCookieJar: enabled, client: client)
            let requests = await client.requests
            XCTAssertEqual(requests.first?.headers.httpHeader("Cookie"), enabled ? "a=store" : "a=header")
            XCTAssertNil(requests.first?.headers.httpHeader("CookieJar"))
            let cookie = await store.getCookie(url: url.absoluteString)
            XCTAssertEqual(cookie, enabled ? "a=store; sid=1" : "a=store")
        }
    }

    func testLocalRedirectCookieChainAndStoppedBody() async throws {
        let login = URL(string: "https://example.com/login")!
        for enabled in [false, true] {
            for follow in [false, true] {
                LocalNetworkProtocol.reset()
                let store = CookieStore()
                let client = URLSessionHttpClient(protocolClasses: [LocalNetworkProtocol.self])
                let options = try UrlOptions.fromJSON("{\"followRedirects\":\(follow)}")
                let response = try await UrlRequestBuilder.execute(url: login.absoluteString, options: options,
                    cookieStore: store, enabledCookieJar: enabled, client: client)
                XCTAssertEqual(response.code, follow ? 200 : 302)
                XCTAssertEqual(response.body, follow ? "account" : "redirect body")
                XCTAssertEqual(response.url, follow ? "https://example.com/account" : login.absoluteString)
                let requests = LocalNetworkProtocol.requests
                XCTAssertEqual(requests.count, follow ? 2 : 1)
                if follow { XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Cookie"), enabled ? "sid=1" : nil) }
                let cookie = await store.getCookie(url: login.absoluteString)
                XCTAssertEqual(cookie, enabled ? "sid=1" : "")
            }
        }
    }
}

private final class LocalNetworkProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var received: [URLRequest] = []
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return received }
    static func reset() { lock.lock(); defer { lock.unlock() }; received = [] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.received.append(request)
        Self.lock.unlock()
        guard let url = request.url, url.host == "example.com", ["/login", "/account"].contains(url.path) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let login = url.path == "/login"
        let response = HTTPURLResponse(url: url, statusCode: login ? 302 : 200, httpVersion: "HTTP/1.1",
            headerFields: login ? ["Location":"/account", "Set-Cookie":"sid=1; Path=/"] : [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((login ? "redirect body" : "account").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
