import XCTest
@testable import LegadoCore

private final class HostTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 0
    var now: Int64 { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ amount: Int64) { lock.lock(); defer { lock.unlock() }; value += amount }
}

final class HostCacheAndRateTests: XCTestCase {
    func testCachePersistsExpiresAtDeadlineAndDeletes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = HostTestClock()
        clock.advance(10_000)
        let cache = CacheManager(directory: directory, now: { clock.now })
        try await cache.put("finite", value: "value", saveTime: 1)
        try await cache.put("forever", value: "42")
        let second = CacheManager(directory: directory, now: { clock.now })
        let persisted = try await second.get("finite")
        XCTAssertEqual(persisted, "value")
        clock.advance(1000)
        let expired = try await cache.get("finite")
        XCTAssertNil(expired)
        let permanent = try await second.getInt("forever")
        XCTAssertEqual(permanent, 42)
        try await second.delete("forever")
        let missing = try await second.get("forever")
        XCTAssertNil(missing)
        try await cache.put("negative", value: "gone", saveTime: -1)
        let negative = try await cache.get("negative")
        XCTAssertNil(negative)
    }

    func testRateWindowSharedBySourceAndSkip() async throws {
        let clock = HostTestClock()
        let limiter = ConcurrentRateLimiter(now: { clock.now }, sleep: { clock.advance($0) })
        try await limiter.acquire(key: "s", rate: "2/1000")
        try await limiter.acquire(key: "s", rate: "2/1000")
        XCTAssertEqual(clock.now, 0)
        try await limiter.acquire(key: "s", rate: "2/1000")
        XCTAssertEqual(clock.now, 1000)
        try await limiter.acquire(key: "other", rate: "1000")
        try await limiter.acquire(key: "s", rate: "0")
        XCTAssertEqual(clock.now, 1000)
    }

    func testCacheFileExpiryFetchesAgain() async throws {
        let clock = HostTestClock(), client = ReplayHttpClient()
        clock.advance(10_000)
        let cache = CacheManager(directory: nil, now: { clock.now })
        let engine = JsEngine(httpClient: client, cookieStore: CookieStore(), cacheManager: cache)
        let url = URL(string: "https://example.test/file.txt")!
        for body in ["first", "second"] { await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data(body.utf8), finalURL: url)) }
        XCTAssertEqual(try engine.evaluateScript("java.cacheFile('https://example.test/file.txt',1)") as? String, "first")
        clock.advance(1000)
        XCTAssertEqual(try engine.evaluateScript("java.cacheFile('https://example.test/file.txt',1)") as? String, "second")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testExecutorSkipRateLimitAndRateUpdate() async throws {
        let clock = HostTestClock(), client = ReplayHttpClient()
        let limiter = ConcurrentRateLimiter(now: { clock.now }, sleep: { clock.advance($0) })
        let engine = JsEngine(httpClient: client, cookieStore: CookieStore(), cacheManager: CacheManager(directory: nil),
                              networkSource: .init(key: "source", concurrentRate: "1000"), rateLimiter: limiter)
        let url = URL(string: "https://example.test/a")!
        for _ in 0..<4 { await client.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url)) }
        _ = try engine.evaluateScript("java.ajaxAll(['https://example.test/a','https://example.test/a'],true)")
        XCTAssertEqual(clock.now, 0)
        _ = try engine.evaluateScript("java.ajaxAll(['https://example.test/a','https://example.test/a'])")
        XCTAssertEqual(clock.now, 1000)
        await limiter.updateConcurrentRate(key: "source", rate: "2/1000")
        try await limiter.acquire(key: "source", rate: "1000")
        XCTAssertEqual(clock.now, 1000)
        await limiter.updateConcurrentRate(key: "source", rate: "broken")
        try await limiter.acquire(key: "source", rate: "1000")
        XCTAssertEqual(clock.now, 2000)
    }
}
