import Foundation
import XCTest
import LegadoCore
@testable import AppCoreCheck

final class ImportHttpClientTests: XCTestCase {
    private func makeClient() -> any ResponseLimitedHttpClient {
        ImportHttpClient(protocolClasses: [ImportFixtureProtocol.self])
    }

    func testNativeRedirectCallbackUsesTheSamePolicy() async throws {
        let response = try await makeClient().send(.init(url: URL(string: "http://origin.test/nativeUpgrade")!,
                                                       headers: ["Authorization": "Bearer private", "Cookie": "private=1"]),
                                                   maximumResponseBytes: ManagementImport.maximumBytes)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.finalURL.absoluteString, "https://cdn.test/echo")
        let headers = try JSONDecoder().decode([String: String].self, from: response.body)
        XCTAssertNil(headers["authorization"])
        XCTAssertNil(headers["cookie"])
    }

    func testCrossHostAndSameHostUpgradeEachStripCredentials() async throws {
        for (start, final) in [("https://origin.test/upgrade", "https://cdn.test/echo"),
                               ("http://origin.test/sameHostUpgrade", "https://origin.test/echo")] {
            let response = try await makeClient().send(.init(url: URL(string: start)!,
                                                           headers: ["Authorization": "secret", "Cookie": "secret=1"]),
                                                       maximumResponseBytes: ManagementImport.maximumBytes)
            XCTAssertEqual(response.finalURL.absoluteString, final)
            let headers = try JSONDecoder().decode([String: String].self, from: response.body)
            XCTAssertNil(headers["authorization"])
            XCTAssertNil(headers["cookie"])
        }
    }

    func testCrossHostUpgradeStripsCredentialsAndKeepsResponse() async throws {
        let response = try await makeClient().send(.init(url: URL(string: "http://origin.test/upgrade")!,
                                                       headers: ["Authorization": "Bearer private", "Cookie": "private=1", "X-Public": "visible"]),
                                                   maximumResponseBytes: ManagementImport.maximumBytes)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.finalURL.absoluteString, "https://cdn.test/echo")
        let headers = try JSONDecoder().decode([String: String].self, from: response.body)
        XCTAssertNil(headers["authorization"])
        XCTAssertNil(headers["cookie"])
        XCTAssertEqual(headers["x-public"], "visible")
    }

    func testSameOriginRedirectRetainsCredentials() async throws {
        let response = try await makeClient().send(.init(url: URL(string: "https://origin.test/local")!,
                                                       headers: ["Authorization": "Bearer private", "Cookie": "private=1"]),
                                                   maximumResponseBytes: ManagementImport.maximumBytes)
        XCTAssertEqual(response.status, 200)
        let headers = try JSONDecoder().decode([String: String].self, from: response.body)
        XCTAssertEqual(headers["authorization"], "Bearer private")
        XCTAssertEqual(headers["cookie"], "private=1")
    }

    func testFiveRedirectsSucceedAndSixFail() async throws {
        let client = makeClient()
        let response = try await client.send(.init(url: URL(string: "https://origin.test/hops/5")!),
                                             maximumResponseBytes: ManagementImport.maximumBytes)
        XCTAssertEqual(response.status, 200)
        do {
            _ = try await client.send(.init(url: URL(string: "https://origin.test/hops/6")!),
                                      maximumResponseBytes: ManagementImport.maximumBytes)
            XCTFail("第六次跳转必须失败")
        } catch {
            guard case ImportHTTPError.tooManyRedirects = error else { return XCTFail("错误类型不匹配：\(error)") }
        }
    }

    func testDeclaredAndStreamedBodiesStopAt16MiB() async throws {
        for path in ["declared", "streamed"] {
            do {
                _ = try await makeClient().send(.init(url: URL(string: "https://origin.test/\(path)")!),
                                               maximumResponseBytes: ManagementImport.maximumBytes)
                XCTFail("超过 16 MiB 必须失败：\(path)")
            } catch {
                guard case ManagementImportError.tooLarge = error else { return XCTFail("错误类型不匹配：\(error)") }
            }
        }
        let response = try await makeClient().send(.init(url: URL(string: "https://origin.test/boundary")!),
                                                  maximumResponseBytes: ManagementImport.maximumBytes)
        XCTAssertEqual(response.body.count, ManagementImport.maximumBytes)
    }

    func testDefaultLimitAndHTTPSDowngrade() async throws {
        do {
            _ = try await makeClient().send(.init(url: URL(string: "https://origin.test/streamed")!))
            XCTFail("默认请求也必须限制 16 MiB")
        } catch {
            guard case ManagementImportError.tooLarge = error else { return XCTFail("错误类型不匹配：\(error)") }
        }
        do {
            _ = try await makeClient().send(.init(url: URL(string: "https://origin.test/downgrade")!))
            XCTFail("HTTPS 降级必须失败")
        } catch {
            guard case ImportHTTPError.invalidRedirect = error else { return XCTFail("错误类型不匹配：\(error)") }
        }
    }
}

private final class ImportFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
        switch url.path {
        case "/upgrade": status = 302; headers["Location"] = "https://cdn.test/echo"
        case "/sameHostUpgrade": status = 302; headers["Location"] = "https://origin.test/echo"
        case "/downgrade": status = 302; headers["Location"] = "http://origin.test/echo"
        case "/nativeUpgrade":
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": "https://cdn.test/echo"])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "https://cdn.test/echo")!), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
            return
        case "/local": status = 301; headers["Location"] = "/echo"
        case "/declared": headers["Content-Length"] = "16777217"
        case "/streamed", "/boundary": break
        default:
            if url.path.hasPrefix("/hops/"), let count = Int(url.lastPathComponent), count > 0 {
                status = 307
                headers["Location"] = "/hops/\(count - 1)"
            } else {
                let fields = Dictionary((request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
                body = try! JSONEncoder().encode(fields)
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if url.path == "/streamed" || url.path == "/boundary" {
            let chunk = Data(repeating: 65, count: 1024 * 1024)
            for _ in 0..<16 { client?.urlProtocol(self, didLoad: chunk) }
            if url.path == "/streamed" { client?.urlProtocol(self, didLoad: Data([66])) }
        } else { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
