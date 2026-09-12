import Foundation
import XCTest
@testable import LegadoCore

final class RuleAnalyzerTests: XCTestCase {
    // RuleAnalyzer.kt cb664b84d:346-364。
    func testKotlinUnclosedDelimitedInnerRulePosition() throws {
        let analyzer = RuleAnalyzer("{{a")
        XCTAssertEqual(try analyzer.innerRule(start: "{{", end: "}}") { _ in
            XCTFail("无闭标记时不应调用回调")
            return "A"
        }, "{{a")
        XCTAssertEqual(analyzer.position, 2)
    }

    // RuleAnalyzer.kt cb664b84d:316-331,346-364；两种重载共享实例起点。
    func testKotlinInnerRulesMaintainInstanceStart() throws {
        let single = RuleAnalyzer(" @{$.a}")
        try single.trim()
        XCTAssertEqual(try single.innerRule(start: "{$.") { _ in "A" }, "A")
        XCTAssertEqual(try single.innerRule(start: "{$.") { _ in "B" }, "")
        let plain = RuleAnalyzer(" @plain")
        try plain.trim()
        XCTAssertEqual(try plain.innerRule(start: "{$.") { $0 }, "plain")
        XCTAssertEqual(try plain.innerRule(start: "{{", end: "}}") { $0 }, "plain")
        let double = RuleAnalyzer(" @{{a}}")
        try double.trim()
        XCTAssertEqual(try double.innerRule(start: "{{", end: "}}") { _ in "A" }, "A")
        XCTAssertEqual(try double.innerRule(start: "{{", end: "}}") { _ in "B" }, "")
        let mixed = RuleAnalyzer("{$.a}{{b}}tail")
        XCTAssertEqual(try mixed.innerRule(start: "{$.") { _ in "A" }, "A{{b}}tail")
        XCTAssertEqual(try mixed.innerRule(start: "{{", end: "}}") { _ in "B" }, "Btail")
    }

    // RuleAnalyzer.kt cb664b84d:57,169-199；候选位于组内也更新 step。
    func testKotlinGroupedCandidatePreservesStep() throws {
        for separators in [["||"], ["&&", "||", "%%"]] {
            let analyzer = RuleAnalyzer("(a||b)c")
            XCTAssertEqual(try analyzer.splitRule(separators: separators), ["(a||b)c"])
            XCTAssertEqual(analyzer.position, 6)
            XCTAssertEqual(analyzer.step, 2)
            XCTAssertFalse(analyzer.consumeToAny(["missing"]))
            XCTAssertEqual(analyzer.position, 6)
            XCTAssertEqual(analyzer.step, 2)
        }
    }

    // RuleAnalyzer.kt cb664b84d:185,194。
    func testKotlinTopLevelQuotes() throws {
        for code in [false, true] {
            XCTAssertEqual(try RuleAnalyzer("'a||b'||c", code: code).splitRule(separators: ["||"]), ["'a", "b'", "c"])
        }
    }

    // RuleAnalyzer.kt cb664b84d:318,326。
    func testKotlinUnclosedInnerRule() throws {
        let analyzer = RuleAnalyzer("{$.a")
        XCTAssertEqual(try analyzer.innerRule(start: "{$.") { _ in
            XCTFail("未闭合规则不应调用回调")
            return "A"
        }, "")
        XCTAssertEqual(analyzer.position, 3)
    }

    // RuleAnalyzer.kt cb664b84d:123,326。
    func testKotlinEmptyInnerReplacementAdvancesPastGroup() throws {
        var received: [String] = []
        let analyzer = RuleAnalyzer("{$.a}{$.b}")
        XCTAssertEqual(try analyzer.innerRule(start: "{$.") {
            received.append($0)
            return $0 == "$.a" ? "" : "B"
        }, "")
        XCTAssertEqual(received, ["$.a"])
        XCTAssertEqual(analyzer.position, 8)
    }

    // RuleAnalyzer.kt cb664b84d:51,93,133。
    func testKotlinFailedOperationsPreservePosition() {
        let search = RuleAnalyzer("abc")
        XCTAssertTrue(search.consumeTo("b"))
        XCTAssertFalse(search.consumeToAny(["missing"]))
        XCTAssertEqual(search.position, 1)
        for code in [false, true] {
            let analyzer = RuleAnalyzer("x(unclosed")
            XCTAssertTrue(analyzer.consumeTo("("))
            let balanced = code
                ? analyzer.chompCodeBalanced(open: "(", close: ")")
                : analyzer.chompRuleBalanced(open: "(", close: ")")
            XCTAssertFalse(balanced)
            XCTAssertEqual(analyzer.position, 1)
        }
    }

    // RuleAnalyzer.kt cb664b84d:169,194,199,234,293。
    func testKotlinSplitPreservesTailPosition() throws {
        for separators in [["||"], ["&&", "||", "%%"]] {
            for (text, expected, position) in [
                ("a||b", ["a", "b"], 3),
                ("abc", ["abc"], 0),
                ("(a||b)", ["(a||b)"], 6),
                ("a||b(c||d)", ["a", "b(c||d)"], 10)
            ] {
                let analyzer = RuleAnalyzer(text)
                XCTAssertEqual(try analyzer.splitRule(separators: separators), expected)
                XCTAssertEqual(analyzer.position, position, text)
            }
        }
    }

    // RuleAnalyzer.kt cb664b84d:37,57,79；String/Char 索引以 UTF-16 码元计。
    func testKotlinUTF16Positions() throws {
        let analyzer = RuleAnalyzer("😀(中)")
        XCTAssertEqual(analyzer.findToAny(["("]), 2)
        XCTAssertTrue(analyzer.consumeTo("("))
        XCTAssertEqual(analyzer.position, 2)
        XCTAssertTrue(analyzer.chompRuleBalanced(open: "(", close: ")"))
        XCTAssertEqual(analyzer.position, 5)
        let separator = RuleAnalyzer("中😀尾")
        XCTAssertTrue(separator.consumeToAny(["😀"]))
        XCTAssertEqual(separator.step, 2)
        let split = RuleAnalyzer("😀||中😀")
        XCTAssertEqual(try split.splitRule(separators: ["||"]), ["😀", "中😀"])
        XCTAssertEqual(split.position, 4)
        XCTAssertEqual(try RuleAnalyzer("中😀尾😀").splitRule(separators: ["😀"]), ["中", "尾", ""])
    }

    // RuleAnalyzer.kt cb664b84d:16,19。
    func testKotlinNoOpTrimPreservesStart() throws {
        let analyzer = RuleAnalyzer("abc")
        XCTAssertTrue(analyzer.consumeTo("b"))
        try analyzer.trim()
        XCTAssertEqual(try analyzer.splitRule(separators: ["@"]), ["abc"])
    }

    // rule-engine.md:108。
    func testFirstSeparatorWins() throws {
        let analyzer = RuleAnalyzer("a&&b||c&&d%%e")
        XCTAssertEqual(try analyzer.splitRule(separators: ["&&", "||", "%%"]), ["a", "b||c", "d%%e"])
        XCTAssertEqual(analyzer.elementsType, "&&")
    }

    // rule-engine.md:109。
    func testParenthesizedExample() throws {
        let analyzer = RuleAnalyzer("div:matches(a||b)@text||p@text")
        XCTAssertEqual(try analyzer.splitRule(separators: ["&&", "||", "%%"]), ["div:matches(a||b)@text", "p@text"])
        XCTAssertEqual(analyzer.elementsType, "||")
    }

    // rule-engine.md:81-82,109。
    func testNestedGroupsAndQuotes() throws {
        for code in [false, true] {
            let text = "a[x=(b||c)][title='x]||y']%%d%%e"
            XCTAssertEqual(try RuleAnalyzer(text, code: code).splitRule(separators: ["&&", "||", "%%"]), ["a[x=(b||c)][title='x]||y']", "d", "e"])
        }
    }

    // rule-engine.md:88-92,98-101。
    func testEmptyAndSeparatorOnly() throws {
        let empty = RuleAnalyzer("")
        XCTAssertEqual(try empty.splitRule(separators: ["&&", "||"]), [""])
        XCTAssertEqual(empty.elementsType, "")
        let single = RuleAnalyzer("abc")
        XCTAssertEqual(try single.splitRule(separators: ["@"]), ["abc"])
        XCTAssertEqual(single.elementsType, "@")
        XCTAssertEqual(try RuleAnalyzer("&&&&").splitRule(separators: ["&&", "||"]), ["", "", ""])
    }

    // rule-engine.md:90-92,102。
    func testUnclosedGroupIsCheckedWhenSeparatorExists() throws {
        XCTAssertThrowsError(try RuleAnalyzer("a[b&&c").splitRule(separators: ["&&"]))
        XCTAssertEqual(try RuleAnalyzer("a[b").splitRule(separators: ["&&"]), ["a[b"])
    }

    // rule-engine.md:78-81,98；组外未定义转义，按字面查找分隔符。
    func testEscapedSeparators() throws {
        XCTAssertEqual(try RuleAnalyzer(#"a\&&b"#).splitRule(separators: ["&&"]), [#"a\"#, "b"])
        XCTAssertEqual(try RuleAnalyzer(#"a(x\)||y)||z"#).splitRule(separators: ["||"]), [#"a(x\)||y)"#, "z"])
    }

    // rule-engine.md:77。
    func testTrim() throws {
        let analyzer = RuleAnalyzer(" \t@@a@text ")
        try analyzer.trim()
        XCTAssertEqual(try analyzer.splitRule(separators: ["@"]), ["a", "text "])
        for text in ["", "@ \n\t"] {
            XCTAssertThrowsError(try RuleAnalyzer(text).trim())
        }
    }

    // rule-engine.md:78-80；同位置按参数顺序选中。
    func testBasicSearchOperations() {
        let analyzer = RuleAnalyzer("Axx(a)[b]&&c")
        XCTAssertFalse(analyzer.consumeTo("axx"))
        XCTAssertEqual(analyzer.position, 0)
        XCTAssertTrue(analyzer.consumeTo("xx"))
        XCTAssertEqual(analyzer.position, 1)
        XCTAssertEqual(analyzer.findToAny(["[", "("]), 3)
        XCTAssertTrue(analyzer.consumeToAny(["&", "&&"]))
        XCTAssertEqual(analyzer.step, 1)
        XCTAssertEqual(analyzer.position, 9)
    }

    // rule-engine.md:81；规则引号内反斜杠不转义引号。
    func testRuleBalance() {
        let analyzer = RuleAnalyzer(#"('a\')tail"#)
        XCTAssertTrue(analyzer.chompRuleBalanced(open: "(", close: ")"))
        XCTAssertEqual(analyzer.position, 6)
        XCTAssertFalse(RuleAnalyzer("((x)").chompRuleBalanced(open: "(", close: ")"))
        XCTAssertFalse(RuleAnalyzer(#"(x\"#).chompRuleBalanced(open: "(", close: ")"))
    }

    // rule-engine.md:82；方括号主深度非零时不计花括号。
    func testCodeBalance() {
        let analyzer = RuleAnalyzer(#"{'a\'}': [}] }tail"#)
        XCTAssertTrue(analyzer.chompCodeBalanced(open: "{", close: "}"))
        XCTAssertEqual(analyzer.position, 14)
        XCTAssertFalse(RuleAnalyzer(#"('a\')"#).chompCodeBalanced(open: "(", close: ")"))
    }

    // rule-engine.md:114。
    func testBalancedInnerRule() throws {
        var received: [String] = []
        let result = try RuleAnalyzer("x{$.a}y{$.b[0]}z").innerRule(start: "{$.") {
            received.append($0)
            return $0 == "$.a" ? "A" : ""
        }
        XCTAssertEqual(result, "xAy{$.b[0]}z")
        XCTAssertEqual(received, ["$.a", "$.b[0]"])
        XCTAssertEqual(try RuleAnalyzer("{$.a}").innerRule(start: "{$.") { _ in "" }, "")
        XCTAssertEqual(try RuleAnalyzer("plain").innerRule(start: "{$.") { $0 }, "")
    }

    // rule-engine.md:115。
    func testDelimitedInnerRule() throws {
        XCTAssertEqual(try RuleAnalyzer("a{{x}}b{{y}}c").innerRule(start: "{{", end: "}}") { $0.uppercased() }, "aXbYc")
        XCTAssertEqual(try RuleAnalyzer("a{{x}}b").innerRule(start: "{{", end: "}}") { _ in "" }, "ab")
        XCTAssertEqual(try RuleAnalyzer("a{{x").innerRule(start: "{{", end: "}}") { $0 }, "a{{x")
        XCTAssertEqual(try RuleAnalyzer("{{a{{b}}c}}").innerRule(start: "{{", end: "}}") { "[\($0)]" }, "[a{{b]c}}")
    }

    // rule-engine.md:36,51,55,65-67；词法求值由后续层承担，本层保留原文。
    func testLexicalExamplesRemainOpaque() throws {
        for text in ["class.a@text<js>result.trim()</js>", "//a", #"@put:{"key":"rule"}"#, "@get:{key}", "{{expr}}", "$0", "$1", "$12", "a##$1", " a "] {
            XCTAssertEqual(try RuleAnalyzer(text).splitRule(separators: ["&&", "||", "%%"]), [text])
        }
    }

    // golden/README.md:9-164；仅解码，不执行规则。
    func testDecodeGoldenDOMCases() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/Conformance/fixtures/golden/AnalyzeByJSoupDomTest.json"))
        let cases = try JSONDecoder().decode([ConformanceCase].self, from: data)
        XCTAssertEqual(cases.count, 11)
        XCTAssertEqual(cases[0].expect, .string("before\nafter"))
        XCTAssertEqual(cases[4].expect, .stringList(["b"]))
        XCTAssertNil(cases[0].derivedFrom)
        XCTAssertNil(cases[0].verification)
        XCTAssertEqual(try JSONDecoder().decode([ConformanceCase].self, from: JSONEncoder().encode(cases)), cases)
    }

    // golden/README.md:76-98,138-154；扩展元数据结构尚未定义，保留任意 JSON。
    func testDecodeOptionalMetadataAndNullDocument() throws {
        let data = Data(#"{"id":"golden-test-001","source":{"file":"test","method":"test","line":1,"commit":"cb664b84d"},"kind":"js","input":{"document":null,"documentType":"text","rule":"","variables":{"n":1,"b":true,"a":[null]}},"expect":{"type":"error","value":"Error"},"notes":"","requiresAndroid":false,"derivedFrom":["source"],"verification":{"status":"pending"}}"#.utf8)
        let value = try JSONDecoder().decode(ConformanceCase.self, from: data)
        XCTAssertNil(value.input.document)
        XCTAssertEqual(value.expect, .error("Error"))
        XCTAssertNotNil(value.derivedFrom)
        XCTAssertNotNil(value.verification)
        XCTAssertEqual(try JSONDecoder().decode(ConformanceCase.self, from: JSONEncoder().encode(value)), value)
    }
}
