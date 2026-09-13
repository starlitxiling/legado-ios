import XCTest
@testable import LegadoCore

final class HostNetworkReviewTests: XCTestCase {
    private let url = URL(string: "https://review.test/a")!

    private func engine(_ client: any HttpClient, cookieJar: Bool = false) -> JsEngine {
        JsEngine(httpClient: client, cookieStore: CookieStore(), cacheManager: CacheManager(directory: nil),
                 networkSource: .init(key: "https://review.test", enabledCookieJar: cookieJar))
    }

    func testOuterTaskCancellationReleasesBridge() async {
        let entered = expectation(description: "内部操作开始"), exited = expectation(description: "外层取消返回")
        let gate = AsyncStream<Void>.makeStream()
        let outer = Task.detached {
            defer { exited.fulfill() }
            do {
                _ = try HostAsyncBridge.wait {
                    entered.fulfill()
                    for await _ in gate.stream {}
                    return 1
                }
                return false
            } catch { return error is CancellationError }
        }
        await fulfillment(of: [entered], timeout: 2)
        outer.cancel()
        await fulfillment(of: [exited], timeout: 0.5)
        gate.continuation.finish()
        let cancelled = await outer.value
        XCTAssertTrue(cancelled)
    }

    func testCancellationDoesNotWaitForUncooperativeOperation() async {
        let entered = expectation(description: "不可取消操作开始"), exited = expectation(description: "桥接取消返回")
        let gate = ReviewContinuationGate()
        let outer = Task.detached {
            defer { exited.fulfill() }
            do {
                try HostAsyncBridge.wait { await gate.wait(entered: entered) }
                return false
            } catch { return error is CancellationError }
        }
        await fulfillment(of: [entered], timeout: 2)
        outer.cancel()
        await fulfillment(of: [exited], timeout: 0.5)
        await gate.release()
        let cancelled = await outer.value
        XCTAssertTrue(cancelled)
    }

    func testOuterTaskCancellationReleasesRateLimitWait() async throws {
        let entered = expectation(description: "进入限流等待"), exited = expectation(description: "限流取消返回")
        let gate = AsyncStream<Void>.makeStream()
        let limiter = ConcurrentRateLimiter(now: { 0 }, sleep: { _ in
            entered.fulfill()
            for await _ in gate.stream {}
            try Task.checkCancellation()
            throw ReviewCleanupError()
        })
        try await limiter.acquire(key: "source", rate: "1000")
        let outer = Task.detached {
            defer { exited.fulfill() }
            do {
                try HostAsyncBridge.wait { try await limiter.acquire(key: "source", rate: "1000") }
                return false
            } catch { return error is CancellationError }
        }
        await fulfillment(of: [entered], timeout: 2)
        outer.cancel()
        await fulfillment(of: [exited], timeout: 0.5)
        gate.continuation.finish()
        let cancelled = await outer.value
        XCTAssertTrue(cancelled)
    }

    func testCancelledJavaAjaxReturnsCancellationToSwift() async {
        let entered = expectation(description: "请求开始"), exited = expectation(description: "JS 求值取消返回")
        let gate = AsyncStream<Void>.makeStream(), replay = ReplayHttpClient()
        await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url))
        let engine = engine(ReviewGatedClient(replay: replay, gate: gate.stream, entered: entered))
        let outer = Task.detached {
            defer { exited.fulfill() }
            do { _ = try engine.evaluateScript("java.ajax('https://review.test/a')"); return false }
            catch { return error is CancellationError }
        }
        await fulfillment(of: [entered], timeout: 2)
        outer.cancel()
        await fulfillment(of: [exited], timeout: 0.5)
        gate.continuation.finish()
        let cancelled = await outer.value
        XCTAssertTrue(cancelled)
    }

    func testConnectionResponseMaps() async throws {
        let replay = ReplayHttpClient(), engine = engine(replay)
        await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url, headers: ["Set-Cookie":"sid=abc; Path=/"]))
        XCTAssertEqual(try engine.evaluateScript("var r=java.get('https://review.test/a',null);[r.headers().get('Set-Cookie'),r.headers().containsKey('Set-Cookie'),r.headers().keySet()[0],r.headers().size(),r.cookies().get('sid'),r.cookies().sid,r.cookies().containsKey('missing')].join('|')") as? String,
                       "sid=abc; Path=/|true|Set-Cookie|1|abc|abc|false")
    }

    func testStrResponseMethodsAndPropertyCoercion() async throws {
        let replay = ReplayHttpClient(), engine = engine(replay)
        await replay.enqueue(url: url, response: HttpResponse(status: 201, body: Data("body".utf8), finalURL: url, headers: ["X-Test":"yes"]))
        XCTAssertEqual(try engine.evaluateScript("var r=java.connect('https://review.test/a');[r.body(),String(r.body),r.body.toUpperCase(),r.body.length,r.url(),r.code(),Number(r.code),r.headers().get('X-Test'),r.headers.get('X-Test'),r.header('x-test'),r.raw().body[0]].join('|')") as? String,
                       "body|body|BODY|4|https://review.test/a|201|201|yes|yes|yes|98")
        await replay.enqueue(url: url, response: HttpResponse(status: 200, body: Data("array".utf8), finalURL: url))
        XCTAssertEqual(try engine.evaluateScript("java.ajaxAll(['https://review.test/a'])[0].body()") as? String, "array")
    }

    func testWebJsWithoutWebViewUsesHTTPAndIgnoresScript() async throws {
        let replay = ReplayHttpClient(), engine = engine(replay)
        await replay.enqueue(url: url, response: HttpResponse(status: 200, body: Data("http".utf8), finalURL: url))
        let executor = try AnalyzeUrlExecutor(#"https://review.test/a,{"webJs":"throw Error('unused')"}"#, engine: engine)
        let result = try await executor.getStrResponse()
        XCTAssertEqual(result.body, "http")
    }

    func testCookieJarEnabledStoredValueWinsAtTransport() async throws { try await assertCookie(cookieJar: true, expected: "sid=stored; manual=1") }
    func testCookieJarDisabledOptionValueWins() async throws { try await assertCookie(cookieJar: false, expected: "sid=temporary; manual=1") }

    private func assertCookie(cookieJar: Bool, expected: String) async throws {
        let replay = ReplayHttpClient(), engine = engine(replay, cookieJar: cookieJar)
        await engine.cookieStore.setCookie(url: url.absoluteString, cookie: "sid=stored; manual=1")
        await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url))
        _ = try engine.evaluateScript(#"java.ajax('https://review.test/a,{"headers":{"Cookie":"sid=temporary"}}')"#)
        let requests = await replay.requests
        XCTAssertEqual(requests.first?.headers["Cookie"], expected)
    }

    func testTimeoutZeroIsUnlimitedForDirectHostAndExplicitCallTimeout() async throws {
        let replay = ReplayHttpClient(), engine = engine(replay)
        for _ in 0..<2 { await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url)) }
        _ = try engine.evaluateScript("java.get('https://review.test/a',null,0)")
        _ = try engine.evaluateScript("java.ajax('https://review.test/a',0)")
        let requests = await replay.requests
        XCTAssertEqual(requests[0].timeout, TimeInterval.greatestFiniteMagnitude)
        XCTAssertEqual(requests[0].callTimeout, TimeInterval.greatestFiniteMagnitude)
        XCTAssertEqual(requests[1].callTimeout, TimeInterval.greatestFiniteMagnitude)
        XCTAssertThrowsError(try engine.evaluateScript("java.get('https://review.test/a',null,-1)"))
    }

    func testURLTimeoutZeroAndNegativeFallBackToDefault() async throws {
        let replay = ReplayHttpClient(), engine = engine(replay)
        for value in [0, -1] {
            await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url))
            let executor = try AnalyzeUrlExecutor("https://review.test/a,{\"timeout\":\(value)}", engine: engine)
            _ = try await executor.getStrResponse()
        }
        let requests = await replay.requests
        XCTAssertEqual(requests.map(\.timeout), [60, 60])
        XCTAssertEqual(requests.map(\.callTimeout), [60, 60])
    }

    func testZeroTimeoutWorksThroughURLSessionWithOfflineReplay() async throws {
        await ReviewReplayProtocol.replay.enqueue(url: url, response: HttpResponse(status: 200, body: Data("ok".utf8), finalURL: url))
        await ReviewReplayProtocol.replay.enqueue(url: url, response: HttpResponse(status: 200, body: Data("ok".utf8), finalURL: url))
        let engine = engine(URLSessionHttpClient(protocolClasses: [ReviewReplayProtocol.self]))
        XCTAssertEqual(try engine.evaluateScript("java.get('https://review.test/a',null,0).body()") as? String, "ok")
        XCTAssertEqual(try engine.evaluateScript("java.ajax('https://review.test/a',0)") as? String, "ok")
    }
}

private struct ReviewCleanupError: Error {}
private actor ReviewContinuationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(entered: XCTestExpectation) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}
private struct ReviewGatedClient: HttpClient {
    let replay: ReplayHttpClient
    let gate: AsyncStream<Void>
    let entered: XCTestExpectation
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        entered.fulfill()
        for await _ in gate {}
        try Task.checkCancellation()
        return try await replay.send(request)
    }
}

private final class ReviewReplayProtocol: URLProtocol {
    static let replay = ReplayHttpClient()
    private var replayTask: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        replayTask = Task {
            do {
                let response = try await Self.replay.send(HttpRequest(url: request.url!, method: request.httpMethod ?? "GET"))
                let http = HTTPURLResponse(url: response.finalURL, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
                client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: response.body)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { replayTask?.cancel() }
}
