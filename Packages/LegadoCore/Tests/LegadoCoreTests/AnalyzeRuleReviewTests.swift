import Foundation
import XCTest
@testable import LegadoCore

final class AnalyzeRuleReviewTests: XCTestCase {
    // 规格 §5.2、§6；Kotlin AnalyzeByJSoup.kt:75-95、510-517。
    func testCSSModeIsSharedByAllCombinedSelectors() throws {
        let engine = ReviewEngine()
        let parser = AnalyzeRule(content: #"<tag class="p">X</tag><p>Y</p>"#, engines: [.default: engine])
        for separator in ["&&", "||", "%%"] {
            engine.cssModes = []
            let expected = separator == "||" ? ["X"] : ["X", "X"]
            XCTAssertEqual(try parser.getStringList("@CSS:tag.p@text\(separator)tag.p@text"), expected)
            XCTAssertEqual(engine.cssModes, Array(repeating: true, count: expected.count))
        }
        let actual = AnalyzeRule(content: #"<tag class="p">X</tag><p>Y</p>"#, engines: [.default: AnalyzeByJSoup()])
        XCTAssertEqual(try actual.getStringList("@CSS:tag.p@text&&tag.p@text"), ["X", "X"])
        XCTAssertThrowsError(try actual.getStringList("tag.p@text&&@CSS:tag.p@text"))
    }

    // 规格 §6；Kotlin AnalyzeByJSonPath.kt:62、101；AnalyzeByXPath.kt:106、144。
    func testJSONAndXPathCombinationsRecurse() throws {
        for (mode, prefix) in [(RuleMode.json, "@Json:"), (.xpath, "@XPath:")] {
            let engine = ReviewEngine()
            let parser = AnalyzeRule(content: #"{"a":"A","b":"B"}"#, engines: [mode: engine])
            XCTAssertEqual(try parser.getString(prefix + "$.a&&$.missing||$.b"), "A\nB")
            XCTAssertEqual(try parser.getStringList(prefix + "$.a&&$.missing||$.b"), ["A", "B"])
            XCTAssertEqual(try parser.getStringList(prefix + "$.a%%$.missing||$.b"), ["A", "B"])
            XCTAssertFalse(engine.rules.contains { $0.contains("&&") || $0.contains("||") || $0.contains("%%") })
        }
    }

    // 规格 §4、§6；Kotlin AnalyzeByJSoup.kt:49-50；AnalyzeRule.kt:361。
    func testEmptyDefaultCombinationRemainsNullBeforeReplacement() throws {
        let parser = AnalyzeRule(content: "<p>Y</p>", engines: [.default: ReviewEngine()])
        XCTAssertEqual(try parser.getString("tag.a@text&&tag.b@text##^$##fallback"), "")
        XCTAssertEqual(try parser.getStringList("tag.a@text&&tag.b@text##^$##fallback"), [])
        let actual = AnalyzeRule(content: "<p>Y</p>", engines: [.default: AnalyzeByJSoup()])
        XCTAssertEqual(try actual.getString("tag.a@text&&tag.b@text##^$##fallback"), "")
    }

    // 规格 §7.1、§8.3；Kotlin AnalyzeRule.kt:585、826-834，缺失字段保留缓存值。
    func testCachedTemplateRetainsMissingReplacementFields() throws {
        let parser = AnalyzeRule(content: "document", ruleData: RuleVariableStore())
        parser.put("n", value: "x##x##A###")
        XCTAssertEqual(try parser.getString("@get:{n}"), "A")
        parser.put("n", value: "y")
        XCTAssertEqual(try parser.getString("@get:{n}"), "")
        parser.put("n", value: "yy##y")
        XCTAssertEqual(try parser.getString("@get:{n}"), "A")
        parser.put("n", value: "yy##y##B")
        XCTAssertEqual(try parser.getString("@get:{n}"), "B")
        XCTAssertEqual(try parser.getString("other@get:{n}"), "otherBB")
    }

    // 规格 §4、§10；Kotlin AnalyzeRule.kt:374-380 的 URL 后处理仅在 isUrl 为真时执行。
    func testBaseURLDoesNotSkipNonURLEntrypoints() throws {
        let object: [String: Any] = [
            "id": "review-base-url", "kind": "regex",
            "source": ["file": "AnalyzeRule.kt", "method": "getElement", "line": 388, "commit": "cb664b84d"],
            "input": ["document": "A1", "documentType": "text", "rule": ":([A-Z])([0-9])", "baseUrl": "https://example.test/", "variables": ["operation": "AnalyzeRule.getElement"]],
            "expect": ["type": "stringList", "value": ["A1", "A", "1"]], "notes": "", "requiresAndroid": false
        ]
        let fixture = try JSONDecoder().decode(ConformanceCase.self, from: JSONSerialization.data(withJSONObject: object))
        let result = ConformanceRunner.run([fixture]).results[0]
        XCTAssertEqual(result.status, .passed, result.detail)
        for operation in ["AnalyzeRule.getString", "AnalyzeRule.getStringList"] {
            var fixtureObject = object
            fixtureObject["input"] = ["document": "text", "documentType": "text", "rule": "@get:{n}", "baseUrl": "https://example.test/",
                "variables": ["operation": operation, "locals": ["n": "A"]]]
            fixtureObject["expect"] = operation == "AnalyzeRule.getString" ? ["type": "string", "value": "A"] as [String: Any] : ["type": "stringList", "value": ["A"]]
            let normal = try JSONDecoder().decode(ConformanceCase.self, from: JSONSerialization.data(withJSONObject: fixtureObject))
            XCTAssertEqual(ConformanceRunner.run([normal]).results[0].status, .passed)
            fixtureObject["input"] = ["document": "text", "documentType": "text", "rule": "@get:{n}",
                "variables": ["operation": operation, "locals": ["n": "A"], "isUrl": true]]
            let url = try JSONDecoder().decode(ConformanceCase.self, from: JSONSerialization.data(withJSONObject: fixtureObject))
            let skipped = ConformanceRunner.run([url]).results[0]
            XCTAssertEqual(skipped.status, .skipped)
            XCTAssertEqual(skipped.detail, "本单元尚未接入 URL 后处理")
        }
    }

    // 规格 §4、§11；Kotlin AnalyzeRule.kt:367-372：仅单串入口默认执行 HTML4 反转义。
    func testStringUnescapesHTML4Entities() throws {
        let parser = AnalyzeRule(content: "document")
        parser.setLocal("n", value: "A&amp;B &copy; &#65; &#x1F600; &apos; &unknown; &amp;lt; &amp")
        XCTAssertEqual(try parser.getString("@get:{n}"), "A&B © A 😀 &apos; &unknown; &lt; &amp")
        XCTAssertEqual(try parser.getStringList("@get:{n}"), ["A&amp;B &copy; &#65; &#x1F600; &apos; &unknown; &amp;lt; &amp"])
        XCTAssertEqual(try parser.getString("@get:{n}", unescape: false), parser.get("n"))
    }
}

private final class ReviewEngine: SelectorEngine {
    var cssModes: [Bool] = []
    var rules: [String] = []
    func evaluate(_ rule: String, content: Any, operation: RuleOperation, context: AnalyzeRule) throws -> Any? {
        rules.append(rule)
        let values: [String]
        switch rule {
        case "@CSS:tag.p@text": values = ["X"]
        case "tag.p@text": values = ["Y"]
        case "$.a": values = ["A"]
        case "$.b": values = ["B"]
        default: values = []
        }
        if operation == .string { return values.isEmpty ? nil : values.joined(separator: "\n") }
        return values
    }
    func evaluate(_ rule: String, content: Any, operation: RuleOperation, isCSS: Bool, context: AnalyzeRule) throws -> Any? {
        cssModes.append(isCSS)
        return try evaluate(isCSS ? "@CSS:" + rule : rule, content: content, operation: operation, context: context)
    }
}
