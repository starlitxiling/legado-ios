import XCTest
@testable import LegadoCore

final class UrlPipelineTests: XCTestCase {
    func testKotlinPagePatternAndBounds() throws {
        let engine = JsEngine(httpClient: ReplayHttpClient())
        func rule(_ value: String, page: Int) throws -> String {
            try AnalyzeUrlExecutor(value, engine: engine, bindings: ["page": page]).ruleURL
        }
        XCTAssertEqual(try rule("https://page.test/<one,two>", page: 99), "https://page.test/two")
        XCTAssertEqual(try rule("https://page.test/<>", page: 1), "https://page.test/")
        XCTAssertEqual(try rule("https://page.test/<a<b,c>", page: 1), "https://page.test/a<b")
        XCTAssertEqual(try rule("https://page.test/<a\nb,c>", page: 1), "https://page.test/<a\nb,c>")
        XCTAssertEqual(try rule("https://page.test/<　a　,b>", page: 1), "https://page.test/　a　")
        XCTAssertEqual(try rule("https://page.test/plain", page: 0), "https://page.test/plain")
        XCTAssertThrowsError(try rule("https://page.test/<a,b>", page: 0))
        XCTAssertThrowsError(try rule("https://page.test/<a,b>", page: -1))
    }

    func testCustomURLKeepsAttributesAndRemovesNull() throws {
        let url = CustomUrl(#"https://custom.test/path, {"method":"POST","serverID":3,"headers":{"X":"v"}}"#)
        XCTAssertEqual(url.getUrl(), "https://custom.test/path")
        try url.putAttribute("serverID", 7).putAttribute("method", nil)
        XCTAssertEqual(UrlOptions.parse(url.description).options.serverID, 7)
        XCTAssertNil(try url.getAttr()["method"])
        XCTAssertEqual((try url.getAttr()["headers"] as? [String: String])?["X"], "v")
        let invalid = CustomUrl("https://custom.test/path,{broken")
        XCTAssertEqual(invalid.description, "https://custom.test/path")
        XCTAssertThrowsError(try url.putAttribute("bad", Date()))
    }
}
