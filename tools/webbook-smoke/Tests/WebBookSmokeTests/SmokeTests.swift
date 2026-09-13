import XCTest
import LegadoCore
@testable import WebBookSmoke

final class SmokeTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/Conformance/fixtures/webbook")

    func testOfflineJourney() async throws {
        let client = ReplayHttpClient()
        for (path, file) in [("/search?key=demo&page=1", "search.html"), ("/book/1", "info.html"),
                             ("/toc/1", "toc1.html"), ("/toc/2", "toc2.html"),
                             ("/read/1", "content1.html"), ("/read/1-2", "content2.html"),
                             ("/read/1-3", "content3.html"), ("/read/2", "content3.html")] {
            let url = URL(string: "https://example.invalid" + path)!
            var body = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            if path == "/read/2" { body = body.replacingOccurrences(of: "class=\"next\"", with: "class=\"end\"") }
            await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data(body.utf8), finalURL: url))
        }
        var output: [String] = []
        let options = try SmokeOptions(arguments: ["--source", root.appendingPathComponent("source.json").path,
                                                  "--keyword", "demo", "--timeout", "3"])
        let report = try await runSmoke(options: options, client: client, emit: { output.append($0) })
        XCTAssertEqual(report.searchCount, 1)
        XCTAssertEqual(report.chapterCount, 2)
        XCTAssertEqual(report.contentCount, 2)
        XCTAssertTrue(output.contains(where: { $0.contains("航海记") && $0.contains("林舟") }))
        XCTAssertTrue(output.contains(where: { $0.contains("海风吹来") }))
        XCTAssertFalse(output.joined().contains("https://"))
        XCTAssertFalse(output.joined().contains("/book/1"))
        let requests = await client.requests
        XCTAssertEqual(requests.count, 8)
        XCTAssertTrue(requests.allSatisfy { $0.timeout == 3 && $0.callTimeout == 3 })
    }

    func testInvalidArgumentsAndRedaction() throws {
        for extra in [["--pick", "-1"], ["--chapters", "0"], ["--timeout", "nan"], ["--unknown", "x"]] {
            XCTAssertThrowsError(try SmokeOptions(arguments: ["--source", "x", "--keyword", "x"] + extra))
        }
        let output = safeText("正文 https://user:password@example.invalid/a?token=secret Cookie: private-value")
        XCTAssertFalse(output.contains("password"))
        XCTAssertFalse(output.contains("secret"))
        XCTAssertFalse(output.contains("private-value"))
        XCTAssertEqual(safeError(WebBookError.httpStatus(403, "https://secret.invalid/token")), "WebBookError.httpStatus(403)")
    }

    func testFailureRetainsStageWithoutRequestDetails() async throws {
        let client = ReplayHttpClient()
        let url = URL(string: "https://example.invalid/search?key=private&page=1")!
        await client.enqueue(url: url, response: HttpResponse(status: 403, finalURL: url,
                                                             headers: ["Authorization": "private-token"]))
        let options = try SmokeOptions(arguments: ["--source", root.appendingPathComponent("source.json").path,
                                                  "--keyword", "private"])
        var output: [String] = []
        do {
            _ = try await runSmoke(options: options, client: client, emit: { output.append($0) })
            XCTFail("HTTP 失败必须终止流程")
        } catch let failure as SmokeFailure {
            XCTAssertEqual(failure.stage, "搜索")
            XCTAssertEqual(failure.context, "关键词长度=7，page=1")
            XCTAssertEqual(failure.errorCase, "WebBookError.httpStatus(403)")
            XCTAssertFalse(output.joined().contains("private"))
            XCTAssertTrue(output.contains(where: { $0.contains("搜索失败，耗时") }))
        }
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }
}
