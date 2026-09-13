import XCTest
@testable import LegadoCore

final class WebDavLimitTests: XCTestCase {
    final class Counter { var reads = 0; var cancelled = false }
    struct Bytes: AsyncSequence, AsyncIteratorProtocol {
        typealias Element = UInt8
        let counter: Counter
        let count: Int
        func makeAsyncIterator() -> Bytes { self }
        mutating func next() async -> UInt8? {
            guard counter.reads < count else { return nil }
            counter.reads += 1
            return 42
        }
    }

    func testUnknownOrFalseLengthStopsAndCancelsBeforeBufferingOverflow() async throws {
        for length: Int64 in [-1, 1] {
            let counter = Counter()
            do {
                _ = try await BoundedHTTPBody.read(Bytes(counter: counter, count: 100), expectedLength: length, limit: 4, cancel: { counter.cancelled = true })
                XCTFail("应拒绝超量响应")
            } catch WebDavError.responseTooLarge {}
            XCTAssertEqual(counter.reads, 5)
            XCTAssertTrue(counter.cancelled)
        }
    }

    func testDeclaredOversizeDoesNotReadBodyAndBoundarySucceeds() async throws {
        let counter = Counter()
        do {
            _ = try await BoundedHTTPBody.read(Bytes(counter: counter, count: 100), expectedLength: 100, limit: 4, cancel: { counter.cancelled = true })
            XCTFail("应先拒绝过大的响应头")
        } catch WebDavError.responseTooLarge {}
        XCTAssertEqual(counter.reads, 0)
        XCTAssertTrue(counter.cancelled)
        let bytes = try await BoundedHTTPBody.read(Bytes(counter: Counter(), count: 4), expectedLength: 4, limit: 4, cancel: {})
        XCTAssertEqual(bytes, Data(repeating: 42, count: 4))
    }

    func testDownloadLimitIsPassedToReplayAndMetadataCheckedBeforeGET() async throws {
        let replay = ReplayHttpClient()
        let url = URL(string: "https://example.invalid/backup.zip")!
        let client = WebDavClient(baseURL: url, username: "u", password: "p", httpClient: replay)
        let source = WebDavBackupSource(client: client, maximumDownloadSize: 4)
        await replay.enqueue(url: url, response: HttpResponse(status: 200, body: Data(repeating: 0, count: 5), finalURL: url))
        do { _ = try await source.downloadToTemporaryFile(WebDavFile(url: url, displayName: "backup.zip")); XCTFail("应拒绝写入超量下载") }
        catch WebDavError.responseTooLarge {}
        do { _ = try await source.download(WebDavFile(url: url, displayName: "backup.zip", size: 5)); XCTFail("应拒绝过大的列表条目") }
        catch WebDavError.responseTooLarge {}
        let requests = await replay.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testURLSessionTransportRejectsFakeOversizeResponses() async throws {
        for declared in [true, false] {
            LimitURLProtocol.declaredLength = declared
            let client = BoundedURLSessionHttpClient(protocolClasses: [LimitURLProtocol.self])
            do {
                _ = try await client.send(HttpRequest(url: URL(string: "https://fixture.invalid/oversize")!, timeout: 1, callTimeout: 1), maximumResponseBytes: 4)
                XCTFail("应取消传输")
            } catch WebDavError.responseTooLarge {}
        }
    }

    func testUnboundedClientIsRejectedBeforeRequest() async throws {
        let client = WebDavClient(baseURL: URL(string: "https://fixture.invalid/")!, username: "u", password: "p", httpClient: UnboundedClient())
        do {
            _ = try await WebDavBackupSource(client: client).download(WebDavFile(url: URL(string: "https://fixture.invalid/backup.zip")!, displayName: "backup.zip"))
            XCTFail("应拒绝缺少限流能力的客户端")
        } catch WebDavError.responseLimitUnavailable {}
    }

    func testOrdinaryURLSessionClientBackupDownloadRequiresLimitCapability() async throws {
        let url = URL(string: "https://fixture.invalid/backup.zip")!
        let client = WebDavClient(baseURL: url, username: "u", password: "p",
                                  httpClient: URLSessionHttpClient(protocolClasses: [RejectRequestURLProtocol.self]))
        do {
            _ = try await WebDavBackupSource(client: client).download(WebDavFile(url: url, displayName: "backup.zip"))
            XCTFail("普通 URLSessionHttpClient 应在 GET 前被拒绝")
        } catch WebDavError.responseLimitUnavailable {}
    }

    func testURLSessionTransportAcceptsEmptyAndExactBoundaryBodies() async throws {
        defer { LimitURLProtocol.bodySize = 100 }
        for size in [0, 4] {
            LimitURLProtocol.bodySize = size
            LimitURLProtocol.declaredLength = true
            let client = BoundedURLSessionHttpClient(protocolClasses: [LimitURLProtocol.self])
            let response = try await client.send(HttpRequest(url: URL(string: "https://fixture.invalid/bounded")!, timeout: 1, callTimeout: 1), maximumResponseBytes: size)
            XCTAssertEqual(response.status, 200)
            XCTAssertEqual(response.body, Data(repeating: 0, count: size))
        }
    }
}

private struct UnboundedClient: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        XCTFail("不应发出请求")
        throw WebDavError.invalidURL
    }
}

private final class RejectRequestURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTFail("能力检查失败后不应发出请求")
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}

private final class LimitURLProtocol: URLProtocol {
    static var declaredLength = false
    static var bodySize = 100
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: Self.declaredLength ? ["Content-Length": String(Self.bodySize)] : [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if Self.bodySize > 0 { client?.urlProtocol(self, didLoad: Data(repeating: 0, count: Self.bodySize)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
