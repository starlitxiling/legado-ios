import XCTest
@testable import LegadoCore

final class NetworkRoutingTests: XCTestCase {
    func testProxyParsingCredentialsAndConfiguration() throws {
        let proxy = try HttpProxy("http://name:p%40ss@proxy.test:8080")
        XCTAssertEqual(proxy.host, "proxy.test")
        XCTAssertEqual(proxy.port, 8080)
        XCTAssertEqual(proxy.username, "name")
        XCTAssertEqual(proxy.password, "p@ss")
        XCTAssertEqual(proxy.dictionary["HTTPEnable"] as? Int, 1)
        XCTAssertEqual(proxy.dictionary["HTTPSProxy"] as? String, "proxy.test")
        XCTAssertFalse(proxy.description.contains("name"))
        XCTAssertFalse(proxy.description.contains("p@ss"))
        let legacy = try HttpProxy("SOCKS5://proxy.test:1080@name@p@ss")
        XCTAssertEqual(legacy.password, "p@ss")
        XCTAssertEqual(legacy.dictionary["SOCKSEnable"] as? Int, 1)
        let configuration = URLSessionConfiguration.ephemeral
        legacy.apply(to: configuration)
        XCTAssertEqual(configuration.proxyConfigurations.count, 1)
        XCTAssertEqual(configuration.proxyConfigurations.first?.allowFailover, false)
        XCTAssertEqual(try HttpProxy("socks4://[::1]:1080").host, "::1")
        for invalid in ["http://proxy.test", "http://proxy.test:0", "https://proxy.test:80", "http://proxy.test:80/path",
                        "http://proxy.test:80?x=1", "http://a:b@c@proxy.test:80", "socks4://name:pass@proxy.test:80", "socks5://name:@proxy.test:80"] {
            XCTAssertThrowsError(try HttpProxy(invalid), invalid)
        }
    }

    func testRequestBuilderConsumesProxyAndDNSWithoutLeakingHeaders() throws {
        let proxied = try UrlRequestBuilder.build(url: "https://route.test/", sourceHeaderJSON: #"{"proxy":"http://proxy.test:8080","X-Test":"yes"}"#)
        XCTAssertEqual(proxied.proxy?.port, 8080)
        XCTAssertNil(proxied.headers["proxy"])
        let options = try UrlOptions.fromJSON(#"{"resolveIp":"192.0.2.1,[2001:db8::1]"}"#)
        let request = try UrlRequestBuilder.build(url: "https://route.test/", options: options)
        XCTAssertEqual(request.hostAddresses["route.test"], ["192.0.2.1", "2001:db8:0:0:0:0:0:1"])
        XCTAssertThrowsError(try UrlRequestBuilder.build(url: "https://route.test/", options: options,
            sourceHeaderJSON: #"{"proxy":"http://proxy.test:8080"}"#))
    }

    func testRouteKeepsLogicalIdentityAndScopesHostOverrides() throws {
        var request = HttpRequest(url: URL(string: "https://route.test:8443/path?q=1")!)
        request.hostAddresses = ["route.test": ["192.0.2.3"]]
        let route = try NetworkRoute(request: request)
        XCTAssertEqual(route.request.url.host, "192.0.2.3")
        XCTAssertEqual(route.request.headers["Host"], "route.test:8443")
        XCTAssertEqual(route.tlsHost, "route.test")
        XCTAssertEqual(route.logicalURL, request.url)
        request.url = URL(string: "https://other.test/path")!
        XCTAssertEqual(try NetworkRoute(request: request).request.url.host, "other.test")
        let hosts = try CustomHosts(#"{"ROUTE.TEST":["192.0.2.1","2001:db8::2"],"other.test":"192.0.2.2"}"#)
        XCTAssertEqual(hosts.addresses["route.test"]?.count, 2)
        XCTAssertThrowsError(try CustomHosts(#"{"route.test":"not-an-ip"}"#))
        XCTAssertThrowsError(try CustomHosts("[]"))
    }

    func testTransportRoutesThroughFakeProtocolAndReusesSession() async throws {
        let client = URLSessionHttpClient(protocolClasses: [RoutingURLProtocol.self])
        var request = HttpRequest(url: URL(string: "https://route.test/path")!)
        request.hostAddresses = ["route.test": ["192.0.2.9"]]
        for _ in 0..<2 {
            let response = try await client.send(request)
            XCTAssertEqual(response.finalURL, request.url)
            XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "192.0.2.9|route.test")
        }
        XCTAssertEqual(client.cachedSessionCount, 1)
    }

    func testIPv6AndPreferenceHostPrecedence() async throws {
        let transport = URLSessionHttpClient(protocolClasses: [RoutingURLProtocol.self])
        let client = PreferenceHttpClient(underlying: transport, userAgent: { "test" },
            customHosts: { #"{"route.test":"192.0.2.5"}"# })
        var request = HttpRequest(url: URL(string: "http://route.test/path")!)
        request.hostAddresses = ["route.test": ["2001:db8::9"]]
        let response = try await client.send(request)
        XCTAssertEqual(response.finalURL, request.url)
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "2001:db8:0:0:0:0:0:9|route.test")
        request.hostAddresses = [:]
        let fallback = try await client.send(request)
        XCTAssertEqual(String(decoding: fallback.body, as: UTF8.self), "192.0.2.5|route.test")
    }

    func testAddressFallbackAndUnlimitedCallBudget() async throws {
        let client = URLSessionHttpClient(protocolClasses: [RoutingURLProtocol.self])
        let request = HttpRequest(url: URL(string: "http://route.test/path")!, callTimeout: .greatestFiniteMagnitude,
            hostAddresses: ["route.test": ["192.0.2.1", "192.0.2.9"]])
        let response = try await client.send(request)
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "192.0.2.9|route.test")
    }

    func testRedirectDropsForeignCredentialsAndHonorsDAVScope() async throws {
        let client = URLSessionHttpClient(protocolClasses: [RoutingURLProtocol.self])
        let store = CookieStore()
        await store.setCookie(url: "https://foreign.test/", cookie: "target=1")
        var request = HttpRequest(url: URL(string: "https://route.test/redirect")!, method: "POST",
            headers: ["Authorization": "private", "Cookie": "secret=1", "Content-Type": "application/json"],
            body: Data("{}".utf8), enabledCookieJar: true, hostAddresses: ["route.test": ["192.0.2.9"]])
        let response = try await client.send(request, cookieStore: store)
        XCTAssertEqual(response.finalURL.absoluteString, "https://foreign.test/credentials")
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "GET||target=1||")
        request.confinesRedirectsToOrigin = true
        let stopped = try await client.send(request, cookieStore: store)
        XCTAssertEqual(stopped.status, 302)
        XCTAssertEqual(stopped.finalURL, request.url)
    }

    func testSessionPoolSeparatesProxyCredentialsAndEvicts() throws {
        let pool = HTTPSessionPool(protocolClasses: [RoutingURLProtocol.self])
        var request = HttpRequest(url: URL(string: "http://route.test/")!)
        request.proxy = try HttpProxy("http://a:one@proxy.test:8080")
        let first = pool.entry(for: try NetworkRoute(request: request))
        let again = pool.entry(for: try NetworkRoute(request: request))
        XCTAssertTrue(first.session === again.session)
        request.proxy = try HttpProxy("http://a:two@proxy.test:8080")
        XCTAssertFalse(first.session === pool.entry(for: try NetworkRoute(request: request)).session)
        for port in 9000..<9040 {
            request.proxy = try HttpProxy("http://proxy.test:" + String(port))
            _ = pool.entry(for: try NetworkRoute(request: request))
        }
        XCTAssertEqual(pool.count, 32)
    }

    func testExecutorRetainsDNSOptions() async throws {
        let client = ReplayHttpClient()
        let url = URL(string: "https://route.test/")!
        await client.enqueue(url: url, response: .init(status: 200, finalURL: url))
        let engine = JsEngine(httpClient: client)
        _ = try await AnalyzeUrlExecutor(#"https://route.test/,{"dnsIp":"192.0.2.2"}"#, engine: engine).getResponse()
        let requests = await client.requests
        XCTAssertEqual(requests.first?.hostAddresses["route.test"], ["192.0.2.2"])
    }
}


private final class RoutingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.host == "192.0.2.1" {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let redirect = request.url?.path == "/redirect"
        let text: String
        if request.url?.path == "/credentials" {
            text = [request.httpMethod ?? "", request.value(forHTTPHeaderField: "Authorization") ?? "",
                request.value(forHTTPHeaderField: "Cookie") ?? "", request.value(forHTTPHeaderField: "Host") ?? "",
                request.value(forHTTPHeaderField: "Content-Type") ?? ""].joined(separator: "|")
        } else {
            text = (request.url?.host ?? "") + "|" + (request.value(forHTTPHeaderField: "Host") ?? "")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: redirect ? 302 : 200, httpVersion: "HTTP/1.1",
            headerFields: redirect ? ["Location": "https://foreign.test/credentials"] : nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
