import XCTest
@testable import LegadoCore

final class NetworkTests: XCTestCase {
    let url = URL(string: "https://example.com/")!

    func testRequestMapping() throws {
        let options = try UrlOptions.fromJSON(#"{"charset":"GBK","timeout":40000,"followRedirects":false,"headers":{"X-Test":"option"}}"#)
        let request = try UrlRequestBuilder.build(url: "https://example.com/?q=中文", options: options, sourceHeaderJSON: #"{"X-Test":"source"}"#)
        XCTAssertEqual(request.url.absoluteString, "https://example.com/?q=%D6%D0%CE%C4")
        XCTAssertEqual(request.timeout, 40)
        XCTAssertEqual(request.callTimeout, 80)
        XCTAssertFalse(request.followRedirects)
        XCTAssertEqual(request.headers["X-Test"], "option")
        XCTAssertNil(request.headers["User-Agent"])
    }

    func testPostFormsAndJSON() throws {
        let form = try UrlRequestBuilder.build(url: url.absoluteString, options: .fromJSON(#"{"method":"POST","body":"q=中文&token=a==&empty="}"#))
        XCTAssertEqual(String(data: form.body!, encoding: .utf8), "q=%E4%B8%AD%E6%96%87&token=a%3D%3D&empty=")
        XCTAssertTrue(form.headers["Content-Type"]!.hasPrefix("application/x-www-form-urlencoded"))
        let json = try UrlRequestBuilder.build(url: url.absoluteString, options: .fromJSON(#"{"method":"POST","body":"{\"a\":1}"}"#))
        XCTAssertEqual(String(data: json.body!, encoding: .utf8), #"{"a":1}"#)
        XCTAssertEqual(json.headers["Content-Type"], "application/json; charset=UTF-8")
    }

    func testDecoder() throws {
        let bytes = Data([0xD6, 0xD0, 0xCE, 0xC4])
        XCTAssertEqual(try ResponseDecoder.decode(bytes, headers: ["Content-Type":"text/html; charset=GBK"]), "中文")
        let html = Data("<head><meta charset='gb2312'></head>".utf8) + bytes
        XCTAssertTrue(try ResponseDecoder.decode(html).hasSuffix("中文"))
        XCTAssertEqual(try ResponseDecoder.decode(Data([0xEF, 0xBB, 0xBF]) + Data("hello".utf8)), "hello")
        let response = try StrResponse(raw: HttpResponse(status: 404, body: bytes, finalURL: url, headers: ["Content-Type":"text/plain; charset=gbk"]))
        XCTAssertEqual(response.body, "中文")
        XCTAssertEqual(response.raw.body, bytes)
        XCTAssertFalse(response.isSuccessful)
    }

    func testCookieRules() async {
        let store = CookieStore()
        await store.setCookie(url: url.absoluteString, cookie: "a=1; token=a==; empty=; nil=null")
        await store.replaceCookie(url: url.absoluteString, cookie: "a=2; b=3")
        let cookie = await store.getCookie(url: url.absoluteString)
        XCTAssertEqual(cookie, "a=2; token=a==; nil=null; b=3")
        let key = await store.getKey(url: url.absoluteString, key: "token")
        XCTAssertEqual(key, "a==")
        await store.setCookie(url: url.absoluteString, cookie: "z=9")
        let replaced = await store.getCookie(url: url.absoluteString)
        XCTAssertEqual(replaced, "z=9")
        await store.removeCookie(url: url.absoluteString)
        let empty = await store.getCookie(url: url.absoluteString)
        XCTAssertEqual(empty, "")
    }

    func testReplayRetryAndHTTPStatus() async throws {
        let client = ReplayHttpClient()
        await client.enqueue(url: url, response: HttpResponse(status: 500, finalURL: url))
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("ok".utf8), finalURL: url))
        let response = try await UrlRequestBuilder.execute(url: url.absoluteString, options: .fromJSON(#"{"retry":2}"#), client: client)
        XCTAssertEqual(response.body, "ok")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
        await client.enqueue(url: url, response: HttpResponse(status: 302, finalURL: url))
        let redirect = try await UrlRequestBuilder.execute(url: url.absoluteString, options: .fromJSON(#"{"retry":2,"followRedirects":false}"#), client: client)
        XCTAssertEqual(redirect.code, 302)
        do { _ = try await client.send(HttpRequest(url: url)); XCTFail("未匹配应抛错") } catch {}
    }

    func testUnsupportedWebView() throws {
        XCTAssertThrowsError(try UrlRequestBuilder.build(url: url.absoluteString, options: .fromJSON(#"{"webView":true}"#)))
    }

    func testLegacyCharsetsAndHeaderPrecedence() throws {
        for name in ["GBK", "GB2312", "GB18030", "Big5"] {
            let data = "中文".data(using: try ResponseDecoder.encoding(for: name))!
            XCTAssertEqual(try ResponseDecoder.decode(data, headers: ["content-type":"text/plain; charset=\(name)"]), "中文")
        }
        let data = Data("<head><meta charset='gbk'></head>中文".utf8)
        XCTAssertTrue(try ResponseDecoder.decode(data, headers: ["Content-Type":"text/html; charset=utf-8"]).hasSuffix("中文"))
        let meta = Data("<head><meta http-equiv='Content-Type' content='text/html; charset=gbk'></head>".utf8) + Data([0xD6, 0xD0])
        XCTAssertTrue(try ResponseDecoder.decode(meta).hasSuffix("中"))
        XCTAssertThrowsError(try ResponseDecoder.decode(Data(), charset: "not-a-charset"))
    }

    func testReplayPostAndRetryExhaustion() async throws {
        let client = ReplayHttpClient()
        for _ in 0..<3 { await client.enqueue(url: url, method: "POST", response: HttpResponse(status: 503, finalURL: url)) }
        let response = try await UrlRequestBuilder.execute(url: url.absoluteString, options: .fromJSON(#"{"method":"POST","body":"a=b","retry":2}"#), client: client)
        XCTAssertEqual(response.code, 503)
        let requests = await client.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].body, Data("a=b".utf8))
        await client.enqueue(url: url, error: URLError(.timedOut))
        do {
            _ = try await UrlRequestBuilder.execute(url: url.absoluteString, options: .fromJSON(#"{"retry":3}"#), client: client)
            XCTFail("网络异常应直接抛出")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        let afterError = await client.requests
        XCTAssertEqual(afterError.count, 4)
    }

    func testCookieRequestResponseIntegration() async throws {
        let store = CookieStore()
        await store.setCookie(url: url.absoluteString, cookie: "a=store")
        let client = ReplayHttpClient()
        await client.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url, headers: ["Set-Cookie":"b=next; Path=/; HttpOnly"]))
        _ = try await UrlRequestBuilder.execute(url: url.absoluteString, options: .fromJSON(#"{"headers":{"Cookie":"a=header; c=keep"}}"#), cookieStore: store, client: client)
        let request = await client.requests[0]
        XCTAssertEqual(request.headers["Cookie"], "a=header; c=keep")
        let cookie = await store.getCookie(url: url.absoluteString)
        XCTAssertEqual(cookie, "a=store")
    }

    func testURLSessionMapping() throws {
        let source = HttpRequest(url: url, method: "POST", headers: ["X-Test":"yes"], body: Data("body".utf8), timeout: 9)
        let request = URLSessionHttpClient.urlRequest(source)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.httpBody, source.body)
        XCTAssertEqual(request.timeoutInterval, 9)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "yes")
    }

    func testEncodingBoundariesAndHead() throws {
        let plus = try UrlRequestBuilder.build(url: url.absoluteString, options: .fromJSON(#"{"method":"POST","body":"q=a+b"}"#))
        XCTAssertEqual(plus.body, Data("q=a%2Bb".utf8))
        let head = try UrlRequestBuilder.build(url: "https://example.com/?q=%D6%D0", options: .fromJSON(#"{"method":"HEAD","charset":"GBK","timeout":1}"#))
        XCTAssertEqual(head.method, "HEAD")
        XCTAssertNil(head.body)
        XCTAssertEqual(head.url.absoluteString, "https://example.com/?q=%D6%D0")
        XCTAssertEqual(head.callTimeout, 60)
        let custom = try UrlRequestBuilder.build(url: url.absoluteString, options: .fromJSON(#"{"method":"POST","headers":{"content-type":"text/plain; charset=gbk"},"body":"中文"}"#))
        XCTAssertEqual(custom.body, Data([0xD6, 0xD0, 0xCE, 0xC4]))
    }

    func testProxyMetadataAndRawCookieMerge() throws {
        let request = try UrlRequestBuilder.build(url: url.absoluteString, sourceHeaderJSON: #"{"proxy":"http://localhost:1234"}"#)
        XCTAssertNil(request.headers["proxy"])
        XCTAssertEqual(CookieStore.mergeCookieValues("", " a=1; empty="), " a=1; empty=")
        let escaped = try UrlRequestBuilder.build(url: url.absoluteString, options: .fromJSON(#"{"method":"POST","charset":"escape","body":"q=中文"}"#))
        XCTAssertEqual(escaped.body, Data("q=%u4E2D%u6587".utf8))
    }
}
