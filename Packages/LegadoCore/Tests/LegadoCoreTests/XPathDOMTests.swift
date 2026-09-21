import XCTest
import SwiftSoup
@testable import LegadoCore

final class XPathDOMTests: XCTestCase {
    private func parser(_ input: Any) -> AnalyzeRule {
        AnalyzeRule(content: input, engines: [.xpath: AnalyzeByXPath(), .default: AnalyzeByJSoup()])
    }
    func testLegacyBridgeIsExplicitAndMalformedFunctionsFail() throws {
        let legacy = AnalyzeRule(content: "<table><tr><td>X</td></tr></table>", engines: [.xpath: AnalyzeByXPath(useLegacyBridge: true)])
        XCTAssertEqual(try legacy.getStringList("//table/tr/td/text()"), ["X"])
        XCTAssertThrowsError(try parser("<a>A</a>").getString("@XPath:position(1)"))
        XCTAssertThrowsError(try parser("<a>A</a>").getString("//a/unknown()"))
        XCTAssertEqual(try parser("<div id='x' lang='en-US'>A</div>").getString("@XPath:id('x')[lang('en')]/@id"), "x")
        XCTAssertEqual(try parser("<div id='x'>A</div>").getString("@XPath:name(//div/@id)"), "id")
        let xml = parser("<?xml version='1.0'?><root xmlns:p='urn:example'><p:item id='x'/></root>")
        XCTAssertEqual(try xml.getString("@XPath:namespace-uri(//p:item)"), "urn:example")
        XCTAssertEqual(try xml.getString("@XPath:local-name(//p:item)"), "item")
        XCTAssertThrowsError(try parser("<a/>").getString("//missing/invalid-axis::a"))
    }

    func testOriginalParentsHTML5TreeAndEntities() throws {
        let document = try SwiftSoup.parse("<div id='parent'><a>&hopf;</a></div>")
        let link = try XCTUnwrap(document.select("a").first())
        XCTAssertEqual(try parser(link).getStringList("@XPath:../@id"), ["parent"])
        XCTAssertEqual(try parser(link).getStringList("@XPath:./text()"), ["𝕙"])
        XCTAssertEqual(try parser("<table><tr><td>X</td></tr></table>").getStringList("//table/tbody/tr/td/text()"), ["X"])
    }
    func testSelectedNodesKeepAncestorsAfterTemporaryDocumentIsReleased() throws {
        let values = try parser("<div id='parent'><a>A</a></div>").getElements("//a")
        XCTAssertEqual(try parser(values).getStringList("@XPath:ancestor::div/@id"), ["parent"])
        XCTAssertEqual(try parser(values[0]).getString("@CSS:a@text"), "A")
    }
    func testTextBlocksNestedExtensionsAndReverseAxes() throws {
        let input = "<ul><li id='a'>A<b>B</b>C</li><li id='b'>Number <b>12.5</b></li><li id='c'>Last</li></ul>"
        let p = parser(input)
        XCTAssertEqual(try p.getStringList("//li[@id='a']/text()"), ["A", "C"])
        XCTAssertEqual(try p.getStringList("//li[allText()='ABC']/@id"), ["a"])
        XCTAssertEqual(try p.getStringList("//li[num()>10]/@id"), ["b"])
        XCTAssertEqual(try p.getStringList("//li[@id='c']/preceding-sibling::li[1]/@id"), ["b"])
        XCTAssertEqual(try p.getStringList("//li[position() mod 2 = 1]/@id"), ["a", "c"])
        XCTAssertEqual(try p.getStringList("@XPath:(//li)[last()]/@id"), ["c"])
    }
    func testFunctionsPredicatesAndTidyTextCompatibilityAlias() throws {
        let p = parser("<p id='x'>  One <b>Two</b>  Three </p><p id='y'>Four</p>")
        XCTAssertEqual(try p.getStringList("//p[contains(allText(),'Two')]/@id"), ["x"])
        XCTAssertEqual(try p.getStringList("//p[@id='x']/tidyText()"), ["One Two Three"])
        XCTAssertEqual(try p.getString("@XPath:count(//p)"), "2")
        XCTAssertEqual(try p.getString("@XPath:substring('ABCDE',2,3)"), "BCD")
        XCTAssertThrowsError(try p.getStringList("//p[unknown()]"))
    }
}
