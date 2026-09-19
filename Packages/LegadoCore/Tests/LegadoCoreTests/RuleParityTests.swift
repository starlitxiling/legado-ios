import Foundation
import JavaScriptCore
import XCTest
@testable import LegadoCore

final class RuleParityTests: XCTestCase {
    private func parser(_ content: Any) -> AnalyzeRule {
        AnalyzeRule(content: content, engines: [.default: AnalyzeByJSoup(), .xpath: AnalyzeByXPath(),
                                               .json: AnalyzeByJSonPath(), .js: JsEngine()])
    }

    func testKotlinMixedCombinationsSplitOnlyOnce() throws {
        let parser = parser("<p id='B'>A</p>")
        XCTAssertEqual(try parser.getString("@CSS:p@text&&p@id||x"), "A")
        XCTAssertEqual(try parser.getString("@CSS:p@text||p@id&&x"), "A")
        XCTAssertThrowsError(try parser.getString("@CSS:missing@text||p@id&&p@text"))
        XCTAssertEqual(try parser.getStringList("@CSS:p@text&&p@id||x&&p@id"), ["A", "B"])
    }

    func testKotlinMapsUseFirstRuleAsKey() throws {
        let parser = parser(["name": "A &amp; B", "items": ["x", "y"], "count": 42] as [String: Any])
        XCTAssertEqual(try parser.getString("name"), "A & B")
        XCTAssertEqual(try parser.getString("name", unescape: false), "A &amp; B")
        XCTAssertEqual(try parser.getString("name<js>throw new Error('must not run')</js>"), "A & B")
        XCTAssertEqual(try parser.getStringList("items"), ["x", "y"])
        XCTAssertEqual(try parser.getString("count"), "42")
        XCTAssertEqual(try parser.getString("missing"), "")
    }

    func testKotlinJavaScriptObjectUsesFirstRule() throws {
        let context = try XCTUnwrap(JSContext())
        let object = try XCTUnwrap(context.evaluateScript("({name:'A', items:['x','y']})"))
        let parser = parser(object)
        XCTAssertEqual(try parser.getString("name"), "A")
        XCTAssertEqual(try parser.getString("name##A##B"), "B")
        XCTAssertEqual(try parser.getString("@js:result.name"), "A")
        XCTAssertEqual(try parser.getStringList("items"), ["x", "y"])
    }

    func testKotlinDetachedScriptObjectRetainsRuleSemantics() throws {
        let producer = parser("document")
        let object = try XCTUnwrap(producer.getElement("@js:({name:'A', items:['x','y']})"))
        let consumer = parser(object)
        XCTAssertEqual(try consumer.getString("name##A##B"), "B")
        XCTAssertEqual(try consumer.getString("@Json:$.name"), "A")
        XCTAssertEqual(try consumer.getString("@js:result.name"), "A")
        XCTAssertEqual(try consumer.getStringList("@js:result.items"), ["x", "y"])
    }

    func testKotlinJSONPathObjectContinuesUsingJSONPath() throws {
        let producer = parser("{\"items\":[{\"name\":\"A\"}]}")
        let object = try XCTUnwrap(producer.getElements("$.items[*]").first)
        XCTAssertEqual(try parser(object).getString("$.name"), "A")
    }

    func testKotlinHostObjectAndURLOverloads() throws {
        let parser = parser("<a href='next'>A</a>")
        parser.setRedirectUrl("https://example.invalid/book/current")
        XCTAssertEqual(try parser.getString("@js:java.getString('name'+'#'.repeat(2)+'A'+'#'.repeat(2)+'B',{name:'A'})"), "B")
        XCTAssertEqual(try parser.getString("@js:java.getString('a@href',null,true)"), "https://example.invalid/book/next")
        XCTAssertEqual(try parser.getStringList("@js:java.getStringList('links',{links:['next','next']},true)"), ["https://example.invalid/book/next"])
        XCTAssertEqual(try parser.getString("@js:java.setContent({name:'A'}).getString('name'+'#'.repeat(2)+'A'+'#'.repeat(2)+'B')"), "B")
    }

    func testDetachedScriptObjectsDoNotRetainJavaScriptContext() throws {
        let engine = JsEngine()
        weak var context: JSContext?
        engine.libraryInitializer = { context = $0 }
        let parser = AnalyzeRule(content: "", engines: [.js: engine])
        let objects = try parser.getElements("@js:[{name:'A',nested:{value:'B'}}]")
        XCTAssertNil(context)
        let object = try XCTUnwrap(objects.first as? [String: Any])
        XCTAssertEqual(object["name"] as? String, "A")
        XCTAssertEqual((object["nested"] as? [String: Any])?["value"] as? String, "B")
    }

    func testKotlinURLFallbackUsesBaseURL() throws {
        let parser = parser("<p>A</p>")
        parser.scriptBaseUrl = "https://example.invalid/book/"
        XCTAssertEqual(try parser.getString("missing@href", isURL: true), "https://example.invalid/book/")
        XCTAssertEqual(try parser.getString("", isURL: true), "")
    }

    func testKotlinURLResolutionUsesRedirectAndKeepsDataBase() throws {
        let parser = parser("<a href='../chapter?a=1&amp;b=2'>A</a><a href='/second'>B</a>")
        parser.setBaseUrl("https://origin.invalid/book/")
        parser.setBaseUrl(nil)
        parser.setRedirectUrl("https://redirect.invalid/books/toc")
        XCTAssertEqual(try parser.getString("a@href", isURL: true), "https://redirect.invalid/chapter?a=1&b=2")
        XCTAssertEqual(try parser.getString("missing@href", isURL: true), "https://origin.invalid/book/")
        let redirect = parser.redirectUrl
        XCTAssertEqual(parser.setRedirectUrl("data:text/html,hello"), redirect)
        XCTAssertEqual(parser.setRedirectUrl("not a URL"), redirect)
        XCTAssertEqual(try parser.getString("a@href", isURL: true), "https://redirect.invalid/chapter?a=1&b=2")
    }

    func testKotlinURLListResolvesDeduplicatesAndRetainsCurrentURL() throws {
        let parser = parser(["links": ["next", "https://example.invalid/book/next", "", "javascript:void(0)", "data:text/plain,A"]])
        parser.setRedirectUrl("https://example.invalid/book/current")
        XCTAssertEqual(try parser.getStringList("links", isURL: true), [
            "https://example.invalid/book/next", "https://example.invalid/book/current", "data:text/plain,A"
        ])
        XCTAssertNil(try parser.getStringList("", isURL: true))
        XCTAssertEqual(try parser.getStringList("links", content: ["links": ["other"]], isURL: true), ["https://example.invalid/book/other"])
        let context = try WebBookContext(source: BookSource(), client: ReplayHttpClient())
        XCTAssertEqual(try context.urls(parser, rule: "links", base: "https://example.invalid/book/current"), [
            "https://example.invalid/book/next", "https://example.invalid/book/current", "data:text/plain,A"
        ])
    }

    func testKotlinEmptyCSSCombinationThrows() throws {
        let parser = parser("<p>A</p><script>raw</script>")
        XCTAssertThrowsError(try parser.getString("@CSS:p@text&&"))
        XCTAssertThrowsError(try parser.getStringList("@CSS:p@text&&"))
        XCTAssertEqual(try parser.getString("@CSS:"), "raw")
    }

    func testKotlinEmptyRangeSelectionThrows() throws {
        let parser = parser("<p>A</p>")
        XCTAssertThrowsError(try parser.getElements("tag.li[0:-1]"))
        XCTAssertEqual(try parser.getElements("tag.li[0]").count, 0)
        XCTAssertEqual(try parser.getElements("tag.li[0:0]").count, 0)
        XCTAssertEqual(try parser.getElements("tag.li[-2:-1]").count, 0)
    }

    func testKotlinContentChangeAndNullRejection() throws {
        let parser = parser("<p>A</p>")
        XCTAssertEqual(try parser.getString("p@text"), "A")
        XCTAssertEqual(try parser.getString("@XPath://p/text()"), "A")
        try parser.setContent("<p>B</p>")
        XCTAssertEqual(try parser.getString("p@text"), "B")
        XCTAssertEqual(try parser.getString("@XPath://p/text()"), "B")
        try parser.setContent("{\"name\":\"C\"}")
        XCTAssertEqual(try parser.getString("$.name"), "C")
        try parser.setContent("{\"name\":\"D\"}")
        XCTAssertEqual(try parser.getString("$.name"), "D")
        XCTAssertThrowsError(try parser.setContent(nil))
        XCTAssertThrowsError(try parser.setContent(NSNull()))
        XCTAssertEqual(try parser.getString("$.name"), "D")
    }
}
