import Foundation
import XCTest
@testable import LegadoCore

final class SelectorEngineTests: XCTestCase {
    // 规格 L124-130：WebJS 接受原始字符串，四类入口分别解析结果。
    func testWebJSMatrix() throws {
        let engine = MatrixEngine()
        engine.value = #"["a","b"]"#
        let parser = AnalyzeRule(content: "text", engines: [.webJS: engine])
        XCTAssertEqual(try parser.getString("@webjs:script"), #"["a","b"]"#)
        XCTAssertEqual(try parser.getStringList("@webjs:script"), ["a", "b"])
        engine.value = #"{"key":"value"}"#
        XCTAssertEqual(try parser.getElement("@webjs:script") as? [String: String], ["key": "value"])
        engine.value = #"[{"key":"value"}]"#
        XCTAssertEqual(try parser.getElements("@webjs:script") as? [[String: String]], [["key": "value"]])
        engine.value = "plain"
        XCTAssertEqual(try parser.getStringList("@webjs:script"), ["plain"])
        XCTAssertNil(try parser.getElement("@webjs:script"))
        XCTAssertTrue(try parser.getElements("@webjs:script").isEmpty)
    }

    // 规格 L124-130：Default/XPath 单对象入口取元素列表，JSON 单对象入口保留单对象。
    func testSelectorOperationMatrix() throws {
        let engine = MatrixEngine()
        let parser = AnalyzeRule(content: "text", engines: [.default: engine, .xpath: engine, .json: engine, .js: engine])
        _ = try parser.getElement("selector")
        _ = try parser.getElement("//selector")
        _ = try parser.getElement("@Json:$.selector")
        _ = try parser.getElement("@js:script")
        XCTAssertEqual(engine.operations, [.elements, .elements, .element, .string])
    }

    // 规格 L122、L131-135：JavaScript null 不被当成字符串替换；后续参数仍先求值。
    func testScriptNullPropagation() throws {
        let engine = MatrixEngine()
        engine.value = NSNull()
        let parser = AnalyzeRule(content: "text", engines: [.js: engine])
        XCTAssertEqual(try parser.getString("<js>script</js>##null##wrong"), "")
        XCTAssertEqual(try parser.getString("@js:script##null##wrong"), "")
        XCTAssertNil(try parser.getStringList("<js>script</js>##null##wrong"))
    }
}

private final class MatrixEngine: SelectorEngine {
    var value: Any? = "value"
    var operations: [RuleOperation] = []
    func evaluate(_ rule: String, content: Any, operation: RuleOperation, context: AnalyzeRule) throws -> Any? {
        operations.append(operation)
        return value
    }
}
