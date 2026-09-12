import Foundation
import XCTest
@testable import LegadoCore

final class AnalyzeRuleTests: XCTestCase {
    // 规格 L38-53：前缀顺序与 JSON 内容优先级。
    func testPrefixPrecedence() throws {
        let parser = AnalyzeRule(content: "{}")
        XCTAssertEqual(try parser.splitSourceRule("//a").first?.mode, .json)
        XCTAssertEqual(try parser.splitSourceRule("@xPaTh://a").first?.mode, .xpath)
        XCTAssertEqual(try parser.splitSourceRule("@cSs:p@text").first?.rule, "@cSs:p@text")
        XCTAssertEqual(try parser.splitSourceRule("@@p@text").first?.mode, .default)
        XCTAssertEqual(try parser.splitSourceRule("@Json:$.a").first?.rule, "$.a")
    }

    // 规格 L25-34、L343-352：JS 切段、重复 WebJS 切段与黏性正则模式。
    func testSegmentsAndStickyRegex() throws {
        let parser = AnalyzeRule(content: "A1")
        XCTAssertEqual(try parser.splitSourceRule("a<JS>x</JS>b@js:y").map(\.rule), ["a", "x", "b", "y"])
        XCTAssertEqual(try parser.splitSourceRule("<js>@webjs:abcde</js>").map(\.mode), [.js, .webJS])
        XCTAssertEqual(try parser.getElements(":([A-Z])([0-9])").count, 1)
        XCTAssertTrue(parser.isRegex)
        XCTAssertEqual(try parser.getString("@XPath:x"), "@XPath:x")
    }

    // 规格 L64-74、L238-242：模板退化、$0、缺失组与非列表回填。
    func testCaptureTemplates() throws {
        let parser = AnalyzeRule(content: ["whole", "A", NSNull()] as [Any])
        XCTAssertEqual(try parser.getString("$0/$1/$2/$9"), "$0/A//")
        parser.setContent("text")
        XCTAssertEqual(try parser.getString("$1"), "$1")
        XCTAssertEqual(try parser.splitSourceRule("p{{1}}").first?.mode, .regex)
        XCTAssertEqual(try parser.splitSourceRule("p##x##{{1}}").first?.mode, .default)
        XCTAssertEqual(try parser.splitSourceRule("p##x##$1").first?.mode, .default)
    }

    // 规格 L218-242：纯替换、首匹配提取与非法正则降级。
    func testReplacement() throws {
        let parser = AnalyzeRule(content: "a12b34")
        XCTAssertEqual(try parser.getString("##([0-9]+)##<$1>"), "a<12>b<34>")
        XCTAssertEqual(try parser.getString("##[0-9]+##X###"), "X")
        XCTAssertEqual(try parser.getString("##Z##X###"), "")
        XCTAssertEqual(try parser.getString("##[##literal###"), "literal")
        parser.setContent("a[b[")
        XCTAssertEqual(try parser.getString("##[##X"), "aXbX")
        XCTAssertEqual(try parser.getString("##b##$8"), "a[$8[")
    }

    // 规格 L248-259：变量写入目标、空值穿透、本地及实体名称遮蔽。
    func testVariables() throws {
        let chapter = RuleVariableStore(["n": ""], name: "")
        let book = RuleVariableStore(["n": "B", "title": "hidden"], name: "Book")
        let parser = AnalyzeRule(content: "x", chapter: chapter, book: book)
        XCTAssertEqual(parser.get("n"), "B")
        XCTAssertEqual(parser.get("title"), "")
        XCTAssertEqual(parser.get("bookName"), "Book")
        parser.setLocal("n", value: "")
        XCTAssertEqual(parser.get("n"), "")
        parser.put("x", value: "value")
        XCTAssertEqual(chapter.variables["x"], "value")
        parser.put("x", value: nil)
        XCTAssertNil(chapter.variables["x"])
    }

    // 规格 L56-58、L257-258：每次求值重新执行 @put，兼容宽松 JSON。
    func testPutAndRepeatedCompilation() throws {
        let parser = AnalyzeRule(content: "abc", ruleData: RuleVariableStore())
        XCTAssertEqual(try parser.getString("@put:{n:'##a##A'}@get:{n}"), "Abc")
        parser.setContent("abcabc")
        XCTAssertEqual(try parser.getString("@put:{n:'##a##A'}@get:{n}"), "AbcAbc")
        XCTAssertEqual(try parser.getString("@put:{broken}@get:{missing}"), "")
    }

    // 规格 L126-137：正则管线、对象列表不执行 makeUpRule。
    func testRegexEntrypoints() throws {
        let parser = AnalyzeRule(content: "A1 B2")
        XCTAssertEqual(try parser.getElement(":([A-Z])([0-9])") as? [String], ["A1", "A", "1"])
        XCTAssertEqual(try parser.getElements(":[A-Z][0-9]&&([0-9])") as? [[String]], [["1", "1"], ["2", "2"]])
        parser.setContent("a##x##y")
        XCTAssertEqual(try parser.getElements(":a##x##y") as? [[String]], [["a##x##y"]])
        parser.setContent("b ab")
        XCTAssertEqual(try parser.getElements(":(a)?b") as? [[String]], [["b", ""], ["ab", "a"]])
        XCTAssertThrowsError(try parser.getElement(":(a)?b"))
    }

    // 规格 L202-214：字符串列表合并、短路与首个非空列表截断。
    func testListCombination() throws {
        let engine = RecordingEngine(values: ["a": ["x", "y"], "b": ["1"], "c": []])
        let parser = AnalyzeRule(content: "doc", engines: [.default: engine])
        XCTAssertEqual(try parser.getStringList("a&&b"), ["x", "y", "1"])
        XCTAssertEqual(try parser.getStringList("b%%a"), ["1", "x"])
        XCTAssertEqual(try parser.getStringList("c%%a%%b"), ["x", "1", "y"])
        engine.calls = []
        XCTAssertEqual(try parser.getStringList("b||a"), ["1"])
        XCTAssertEqual(engine.calls, ["b"])
    }

    // 规格 L240、L272：内插规则读取整个内容，JS 接收当前结果。
    func testInjectedTemplateEngines() throws {
        let engine = RecordingEngine(values: ["first": "changed", "@CSS:p@text": "original", "expr": 3.0])
        let parser = AnalyzeRule(content: "document", engines: [.default: engine, .js: engine])
        XCTAssertEqual(try parser.getString("first<js>expr</js>{{@CSS:p@text}}"), "original")
        XCTAssertEqual(engine.contents, ["document", "changed", "document"])
        XCTAssertEqual(try parser.getString("value={{expr}}"), "value=3")
    }

    // 规格 L128-137：空入口与未安装的选择器不能假装成功。
    func testEmptyAndUnsupported() throws {
        let parser = AnalyzeRule(content: "abc")
        XCTAssertEqual(try parser.getString(""), "")
        XCTAssertNil(try parser.getStringList(""))
        XCTAssertNil(try parser.getElement(""))
        XCTAssertTrue(try parser.getElements("").isEmpty)
        XCTAssertThrowsError(try parser.getString("tag.p@text"))
        XCTAssertThrowsError(try parser.getString("{{1+2}}"))
        XCTAssertEqual(try parser.getString("@get:{missing}"), "")
    }
}

private final class RecordingEngine: SelectorEngine {
    let values: [String: Any]
    var calls: [String] = []
    var contents: [String] = []
    init(values: [String: Any]) { self.values = values }
    func evaluate(_ rule: String, content: Any, operation: RuleOperation, context: AnalyzeRule) throws -> Any? {
        calls.append(rule)
        contents.append(String(describing: content))
        return values[rule]
    }
}
