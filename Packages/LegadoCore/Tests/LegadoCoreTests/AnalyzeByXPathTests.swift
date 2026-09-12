import Foundation
import XCTest
import SwiftSoup
@testable import LegadoCore

final class AnalyzeByXPathTests: XCTestCase {
    private let html = "<html><body><ul><li id='a'><a href='one'>A<b>B</b>C</a></li><li id='b'><a href='two'>D</a></li></ul></body></html>"

    private func parser(_ content: Any) -> AnalyzeRule {
        AnalyzeRule(content: content, engines: [.xpath: AnalyzeByXPath(), .default: AnalyzeByJSoup()])
    }

    // 规格 §4；AnalyzeByXPath.kt:95-103：每个结果分别转换为字符串。
    func testPathsPredicatesAttributesAndTextNodes() throws {
        let parser = parser(html)
        let cases: [(String, [String])] = [
            ("/html/body/ul/li/a/@href", ["one", "two"]),
            ("@XPath:html/body/ul/li/a/@href", ["one", "two"]),
            ("//li[@id='b']/a/@href", ["two"]),
            ("//a/text()", ["AC", "D"]),
            ("//a[contains(@href,'on')]/@href", ["one"]),
            ("//a[starts-with(@href,'tw')]/@href", ["two"]),
            ("//li[last()]/@id", ["b"]),
            ("//li[1]/@id", ["a"]),
            ("//b/text()", ["B"]),
            ("//li[@id='b']/@id | //li[@id='a']/@id", ["a", "b"]),
            ("//missing/@id", [])
        ]
        for (rule, expected) in cases {
            XCTAssertEqual(try parser.getStringList(rule), expected, rule)
        }
    }

    // 规格 §4；AnalyzeByXPath.kt:17-23、52-61：元素结果继续作为选择上下文。
    func testElementResultsAndRelativeSelection() throws {
        let elements = try parser(html).getElements("//li")
        XCTAssertEqual(elements.count, 2)
        XCTAssertEqual(try parser(elements[0]).getStringList("@XPath:./a/@href"), ["one"])
        XCTAssertEqual(try parser(elements).getStringList("@XPath:./a/@href"), ["one", "two"])
        XCTAssertEqual(try parser(elements[0]).getStringList("@CSS:a@href"), ["one"])
        let element = try SwiftSoup.parse(html).select("li").first()!
        XCTAssertEqual(try parser(element).getStringList("@XPath:./a/@href"), ["one"])
    }

    // 规格 §6；AnalyzeByXPath.kt:57-89、133-154：组合及字符串连接。
    func testCombinationAndStringJoining() throws {
        let parser = parser(html)
        XCTAssertEqual(try parser.getString("//a/@href"), "one\ntwo")
        XCTAssertEqual(try parser.getStringList("//missing || //a/@href"), ["one", "two"])
        XCTAssertEqual(try parser.getStringList("//li/@id %% //a/@href"), ["a", "one", "b", "two"])
        XCTAssertEqual(try parser.getElements("//missing || //li").count, 2)
    }

    // 规格 §11；AnalyzeByXPath.kt:27-40：XML。
    func testXML() throws {
        XCTAssertEqual(try parser("<?xml version='1.0'?><Root><Item>A</Item></Root>").getStringList("//Item/text()"), ["A"])
    }

    // AnalyzeByXPath.kt:17-23：XPath 从原始内容建树，不读取 JSoup 的私有缓存。
    func testIndependentDOMAndContentReset() throws {
        let parser = parser("<div><script id='s'>x</script></div>")
        _ = try parser.getString("div@html")
        XCTAssertEqual(try parser.getStringList("//script/@id"), ["s"])
        parser.setContent("<script id='new'>new</script>")
        XCTAssertEqual(try parser.getStringList("//script/@id"), ["new"])
    }

    // 规格 §11 U7：未核实的扩展显式失败，不能伪装为空匹配。
    func testInvalidAndUnsupportedFunctions() throws {
        for rule in ["//a[", "unknown()"] {
            XCTAssertThrowsError(try parser(html).getStringList("@XPath:" + rule), rule)
        }
        XCTAssertEqual(try parser("<a href='html()'>A</a>").getStringList("//a[@href='html()']/text()"), ["A"])
    }

    // 规格 §11 U7；JsoupXpath README 的 NodeTest：text 为自有文本，allText 包含子孙。
    func testTextAndExtensionProjections() throws {
        let parser = parser("<a>A<b>B</b>C</a><a>  D \n E </a>")
        XCTAssertEqual(try parser.getStringList("//a/text()"), ["AC", "D E"])
        XCTAssertEqual(try parser.getStringList("//a/allText()"), ["ABC", "D E"])
        XCTAssertEqual(try self.parser("<a>A<b>B</b>C</a>").getStringList("//a/html()"), ["A<b>B</b>C"])
        XCTAssertEqual(try self.parser("<a>A<b>B</b>C</a>").getStringList("//a/outerHtml()"), ["<a>A<b>B</b>C</a>"])
        XCTAssertEqual(try self.parser("<a>价格 -12.5，另有 20</a>").getStringList("//a/num()"), ["-12.5"])
    }

    // docs/spec/xpath-compat.md：以下断言记录库差异，不表示 Kotlin 一致性通过。
    func testKnownBridgeDifferences() throws {
        let document = try SwiftSoup.parse("<div id='p'><a>A</a></div>")
        try withExtendedLifetime(document) {
            let original = try document.select("a").first()!
            XCTAssertEqual(try original.parent()?.attr("id"), "p")
            XCTAssertEqual(try parser(original).getStringList("@XPath:../@id"), [])
        }
        let table = "<table><tr><td>X</td></tr></table>"
        XCTAssertEqual(try SwiftSoup.parse(table).select("table > tbody > tr > td").text(), "X")
        XCTAssertEqual(try parser(table).getStringList("//table/tbody/tr/td/text()"), [])
        XCTAssertEqual(try parser(table).getStringList("//table/tr/td/text()"), ["X"])
        XCTAssertEqual(try parser("<td>X</td>").getStringList("//table/tr/td/text()"), ["X"])
        XCTAssertEqual(try SwiftSoup.parse("<a>&hopf;</a>").select("a").text(), "𝕙")
        XCTAssertEqual(try parser("<a>&hopf;</a>").getStringList("//a/text()"), ["&hopf;"])
        let markup = "<div><p>X</p></div>"
        print("xpath-known-serialization libxml2: \(String(reflecting: try parser(markup).getStringList("//div")))")
        print("xpath-known-serialization SwiftSoup: \(String(reflecting: try SwiftSoup.parse(markup).select("div").outerHtml()))")
    }

    // 规格 §4；synthetic-xpath.json 保留原始期望值。
    func testConformanceFixtures() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let cases = try ConformanceRunner.load(directories: [root.appendingPathComponent("Tests/Conformance/fixtures/synthetic")])
            .filter { $0.kind == "xpath" }
        XCTAssertEqual(cases.count, 4)
        for result in ConformanceRunner.run(cases).results {
            print("unit7 \(result.id): \(result.status.rawValue) \(result.detail)")
            XCTAssertEqual(result.status, .passed, result.id + ": " + result.detail)
        }
    }
}
