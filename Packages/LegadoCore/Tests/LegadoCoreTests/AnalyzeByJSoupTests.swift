import Foundation
import XCTest
import SwiftSoup
@testable import LegadoCore

final class AnalyzeByJSoupTests: XCTestCase {
    // 规格 §5.4，L167-177；Kotlin AnalyzeByJSoup.kt:306、315，非空点前缀属于 CSS。
    func testLeadingDotCSSSelectors() throws {
        let html = "<div><span class='x'>A</span><b>B</b><span class='x'>C</span></div>"
        let parser = try AnalyzeByJSoup(html)
        XCTAssertEqual(try parser.getElements(".x").map { $0.tagName() }, ["span", "span"])
        XCTAssertEqual(try parser.getElements(".x[0]").map { $0.tagName() }, ["span"])
        XCTAssertEqual(try parser.getStringList(".x@text"), ["A", "C"])
        XCTAssertEqual(try parser.getStringList(".x[0]@text"), ["A"])
        XCTAssertEqual(try parser.getStringList("tag.div@[0]@text"), ["A"])
    }

    // 规格 §11，L348；Kotlin AnalyzeRule.kt:104-114、154-161，缓存属于内容生命周期。
    func testProtocolDOMLifetime() throws {
        let html = "<span>A<script id='s'>x</script></span>"
        let engine = AnalyzeByJSoup()
        let parser = AnalyzeRule(content: html, engines: [.default: engine])
        XCTAssertEqual(try parser.getStringList("span@html&&script@id"), ["<span>A</span>"])
        XCTAssertEqual(try parser.getStringList("script@id"), [])
        parser.setContent(html)
        XCTAssertEqual(try parser.getStringList("script@id"), ["s"])
        XCTAssertEqual(try parser.getStringList("span@html"), ["<span>A</span>"])
        XCTAssertEqual(try parser.getStringList("script@id"), [])
        let other = AnalyzeRule(content: html, engines: [.default: engine])
        XCTAssertEqual(try other.getStringList("script@id"), ["s"])
        let intermediate = "<script id='intermediate'>y</script>"
        _ = try engine.evaluate("script@html", content: intermediate, operation: .stringList, context: parser)
        XCTAssertEqual(try engine.evaluate("script@id", content: intermediate, operation: .stringList, context: parser) as? [String], ["intermediate"])
        XCTAssertEqual(try parser.getStringList("script@id"), [])
    }

    // 规格 §5.1、§5.3，L147、L162；jsoup 1.23.2 XmlTreeBuilder 初始化关闭 prettyPrint。
    func testXMLSerializationExactCharacters() throws {
        let html = "<?xml version=\"1.0\"?><Item>A</Item>"
        let expected = "<Item>A</Item>"
        let direct = try AnalyzeByJSoup(html).getStringList("Item@all")
        XCTAssertEqual(direct, [expected])
        XCTAssertEqual(direct.first.map { Array($0.utf8) }, Array(expected.utf8))
        let parser = AnalyzeRule(content: html, engines: [.default: AnalyzeByJSoup()])
        XCTAssertEqual(try parser.getStringList("Item@all"), [expected])
    }

    // 规格 §5.1、§5.3，L147、L161-162；XML 配置不得改变 HTML 的默认输出设置。
    func testHTMLDefaultOutputSettings() throws {
        _ = try AnalyzeByJSoup("<?xml version=\"1.0\"?><Item>A</Item>")
        let parser = try AnalyzeByJSoup("<div>A</div>")
        let element = try XCTUnwrap(parser.getElements("div").first)
        let settings = try XCTUnwrap(element.ownerDocument()).outputSettings()
        XCTAssertTrue(settings.prettyPrint())
        XCTAssertFalse(settings.outline())
        XCTAssertEqual(settings.indentAmount(), 1)
        print("HTML probe div: \(try element.outerHtml().debugDescription)")
        let padding = StringBuilder()
        element.indent(padding, 40, settings)
        print("HTML probe indent depth 40: \(padding.toString().debugDescription), utf8Count=\(padding.toString().utf8.count)")
    }

    // 规格 §5.1、§11，L147、L341；自闭合不吞并后续文本，XML 保留大小写。
    func testDocumentParsing() throws {
        let html = try AnalyzeByJSoup("<div>before<a/>after<span>nested</span>end</div>")
        XCTAssertEqual(try html.getStringList("div@textNodes"), ["before\nafter\nend"])
        XCTAssertEqual(try html.getStringList("a@text"), [])
        let xml = try AnalyzeByJSoup("<?xml version=\"1.0\"?><Root><Item>A</Item></Root>")
        let items = try xml.getElements("Item")
        XCTAssertEqual(items.map { $0.tagName() }, ["Item"])
        XCTAssertEqual(try xml.getStringList("Item@text"), ["A"])
    }

    // 规格 §5.2、§5.3、§11，L152、L161、L348；空前缀与空规则不同，html 修改原节点。
    func testEmptyRulesAndDOMMutation() throws {
        let root = try SwiftSoup.parse("<div>A<script>x</script><style>y</style></div>")
        let parser = try AnalyzeByJSoup(root)
        XCTAssertEqual(try parser.getStringList(""), [])
        XCTAssertEqual(try parser.getStringList("@cSs:  "), ["xy"])
        let html = try parser.getStringList("div@html")
        XCTAssertEqual(html.count, 1)
        XCTAssertFalse(html[0].contains("<script"))
        XCTAssertFalse(html[0].contains("<style"))
        XCTAssertEqual(try parser.getStringList("div@text"), ["A"])
        XCTAssertEqual(try parser.getStringList("@CSS:"), [""])
        XCTAssertEqual(try root.select("script, style").size(), 0)
        XCTAssertThrowsError(try parser.getStringList("@@ "))
        XCTAssertThrowsError(try parser.getStringList("tag.div.@text"))
    }

    // 规格 §5.5，L181-187；排除不删除节点，顺序去重、反向和区间边界保持原语义。
    func testIndexOrderAndIdentity() throws {
        let parser = try AnalyzeByJSoup("<ul><li>0</li><li>1</li><li>2</li><li>3</li></ul>")
        let all = try parser.getElements("tag.li")
        let selected = try parser.getElements("tag.li[-1,0,-1]")
        XCTAssertTrue(selected[0] === all[3])
        XCTAssertTrue(selected[1] === all[0])
        XCTAssertEqual(try parser.getStringList("tag.li[-1:0]@text"), ["3", "2", "1", "0"])
        XCTAssertEqual(try parser.getStringList("tag.li[0:3:-1]@text"), ["0", "3"])
        XCTAssertEqual(try parser.getStringList("tag.li[0:3:9]@text"), ["0"])
        XCTAssertEqual(try parser.getStringList("tag.li[1:]@text"), ["1", "2", "3"])
        XCTAssertEqual(try parser.getStringList("tag.li.2:0:2@text"), ["2", "0"])
        _ = try parser.getElements("tag.li[!0,-1]")
        XCTAssertEqual(try parser.getElements("tag.li").count, 4)
        XCTAssertEqual(try parser.getStringList("tag.ul@[0:1]@text"), ["0", "1"])
    }

    // 规格 §5.2、§6，L151、L207-215；CSS 使用最后一个 @，元素 %% 保留首个空列表。
    func testCSSAndDirectCombination() throws {
        let parser = try AnalyzeByJSoup("<a href='x@y'>A</a><a>B</a><b>C</b>")
        XCTAssertEqual(try parser.getStringList("@CSS:a[href='x@y']@text"), ["A"])
        XCTAssertEqual(try parser.getStringList("@CSS:b@text%%a@text"), ["C", "A"])
        XCTAssertEqual(try parser.getStringList("tag.missing@text%%tag.a@text"), ["A", "B"])
        XCTAssertEqual(try parser.getElements("tag.missing%%tag.a").count, 0)
        XCTAssertEqual(try parser.getElements("@CSS:missing%%a").count, 0)
        XCTAssertEqual(try parser.getStringList("a[href]@href"), ["x@y"])
        XCTAssertEqual(try parser.getString("tag.a@text"), "A\nB")
        XCTAssertNil(try parser.getString("missing@text"))
    }

    // 规格 §5、§6、§11，L147-215、L341-350；fixture 保留原入口、期望与状态。
    func testConformanceFixtures() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixtureRoot = root.appendingPathComponent("Tests/Conformance/fixtures")
        let cases = try ConformanceRunner.load(directories: [
            fixtureRoot.appendingPathComponent("golden"), fixtureRoot.appendingPathComponent("synthetic")
        ]).filter { test in
            test.id.hasPrefix("golden-AnalyzeByJSoupDomTest-") ||
            ["default", "combine", "prefix", "empty", "template"].contains { test.id.hasPrefix("synthetic-\($0)-") }
        }
        let report = ConformanceRunner.run(cases)
        for group in ["golden-AnalyzeByJSoupDomTest", "synthetic-default", "synthetic-combine", "synthetic-prefix", "synthetic-empty", "synthetic-template"] {
            let entries = report.results.filter { $0.id.hasPrefix(group + "-") }
            print("unit4 \(group): passed=\(entries.filter { $0.status == .passed }.count), skipped=\(entries.filter { $0.status == .skipped }.count), failed=\(entries.filter { $0.status == .failed }.count), unsupported=\(entries.filter { $0.status == .unsupported }.count)")
        }
        for result in report.results {
            print("unit4 \(result.id): \(result.status.rawValue) \(result.detail)")
            if ["synthetic-template-001", "synthetic-template-002", "synthetic-template-004"].contains(result.id) {
                XCTAssertEqual(result.status, .passed, result.id)
            } else {
                XCTAssertEqual(result.status, .passed, "\(result.id): \(result.detail)")
            }
        }
    }
}
