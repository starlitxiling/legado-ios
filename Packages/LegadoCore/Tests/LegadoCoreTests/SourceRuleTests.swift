import Foundation
import XCTest
@testable import LegadoCore

final class SourceRuleTests: XCTestCase {
    // 规格 L56-58：JSON 标量转字符串，null 子规则按空规则求值。
    func testPutScalarsAndNull() throws {
        let segment = try SourceRule(#"@put:{"flag":true,"n":12,"empty":null}tail"#)
        XCTAssertEqual(segment.putMap, ["flag": "true", "n": "12", "empty": ""])
        XCTAssertEqual(segment.rule, "tail")
        let parser = AnalyzeRule(content: "document", ruleData: RuleVariableStore())
        XCTAssertEqual(try parser.getString(#"@put:{empty:null}@get:{empty}"#), "")
    }

    // 规格 L240：整数浮点无小数，布尔值不能因 NSNumber 桥接变为数字。
    func testInterpolationNumbersAndBooleans() throws {
        let engine = ValueEngine()
        let parser = AnalyzeRule(content: "doc", engines: [.js: engine])
        engine.value = NSNumber(value: true)
        XCTAssertEqual(try parser.getString("{{value}}"), "true")
        engine.value = NSNumber(value: 2.0)
        XCTAssertEqual(try parser.getString("{{value}}"), "2")
        engine.value = -0.0
        XCTAssertEqual(try parser.getString("{{value}}"), "-0")
        engine.value = nil
        XCTAssertEqual(try parser.getString("{{value}}"), "")
    }

    // 规格 L122、L131、L258：缓存参数每次读取新变量；空列表模板保留当前内容。
    func testCachedTemplatesAndEmptyListRule() throws {
        let parser = AnalyzeRule(content: "a\nb", ruleData: RuleVariableStore())
        parser.put("n", value: "A")
        XCTAssertEqual(try parser.getString("@get:{n}"), "A")
        parser.put("n", value: "B")
        XCTAssertEqual(try parser.getString("@get:{n}"), "B")
        XCTAssertEqual(try parser.getStringList("@get:{missing}"), ["a", "b"])
    }

    // 规格 §4 L132；Kotlin AnalyzeRule.kt:413-415：单对象替换也处理 null.toString()。
    func testNullElementReplacement() throws {
        let parser = AnalyzeRule(content: "abc")
        XCTAssertEqual(try parser.getElement(":z##null##empty") as? String, "empty")
    }

    // 规格 L31-34、L71-74：UTF-16 切段、ASCII trim 与每片文本独立拆 $n。
    func testUTF16AndTemplateChunkBoundaries() throws {
        let parser = AnalyzeRule(content: ["whole", "A"])
        XCTAssertEqual(try parser.splitSourceRule(" 😀<js>x</js>尾 ").map(\.rule), ["😀", "x", "尾"])
        XCTAssertEqual(try parser.getString("x##p##@get:{missing}$1"), "x")
        let segment = try SourceRule("p##x##@get:{key}$1")
        XCTAssertEqual(segment.mode, .regex)
        XCTAssertEqual(segment.parameters.last, .capture(1, "$1"))
    }

    // 规格 L34、L258：已缓存规则保留编译模式；新规则遵循黏性正则状态。
    func testCacheRetainsModeAcrossStickyState() throws {
        let parser = AnalyzeRule(content: "a")
        XCTAssertThrowsError(try parser.getString("selector"))
        _ = try parser.getElements(":a")
        XCTAssertThrowsError(try parser.getString("selector"))
        XCTAssertEqual(try parser.getString("newSelector"), "newSelector")
    }

    // 规格 L238-242：两位组号、$0 字面量、空组和非列表语义。
    func testTwoDigitCaptureLimit() throws {
        let parser = AnalyzeRule(content: (0..<13).map(String.init))
        XCTAssertEqual(try parser.getString("$123|$00|$01"), "123|$00|1")
    }
}

private final class ValueEngine: SelectorEngine {
    var value: Any?
    func evaluate(_ rule: String, content: Any, operation: RuleOperation, context: AnalyzeRule) throws -> Any? { value }
}
