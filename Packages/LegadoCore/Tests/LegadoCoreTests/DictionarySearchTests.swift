import XCTest
@testable import LegadoCore

final class DictionarySearchTests: XCTestCase {
    func testURLKeyScriptResponseAndShowRule() async throws {
        let client = ReplayHttpClient()
        let url = URL(string: "https://dictionary.test/?word=hello%20world")!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("<p>Meaning</p>".utf8), finalURL: url))
        let rule = DictRule(name: "Test", urlRule: "https://dictionary.test/?word={{encodeURIComponent(key)}}", showRule: "@CSS:p@text")
        let output = try await rule.search(word: "hello world", client: client)
        XCTAssertEqual(output, "Meaning")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testDataURLBinaryAndRawDisplay() async throws {
        let client = ReplayHttpClient()
        let url = URL(string: "https://dictionary.test/raw")!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("hello".utf8), finalURL: url))
        let raw = DictRule(name: "Raw", urlRule: url.absoluteString)
        let rawOutput = try await raw.search(word: "ignored", client: client)
        XCTAssertEqual(rawOutput, "hello")
        let binary = DictRule(name: "Binary", urlRule: #"data:;base64,{{java.base64Encode(key)}},{"type":"bd"}"#, showRule: "@js:java.hexDecodeToString(result)")
        let decoded = try await binary.search(word: "word", client: ReplayHttpClient())
        XCTAssertEqual(decoded, "word")
    }
}
