import Foundation
import XCTest
@testable import LegadoCore

final class HtmlFormatterTests: XCTestCase {
    // Kotlin NetworkUtils.kt:175–185：URL 拼接保留原字符，不做百分号编码。
    func testImageURLResolutionPreservesCharacters() {
        let base = URL(string: "https://example.com/book/1.html?old=1#old")!
        let cases = [
            ("a b.jpg", "https://example.com/book/a b.jpg"),
            ("//cdn.example.com/a b.jpg", "https://cdn.example.com/a b.jpg"),
            ("/images/a b.jpg", "https://example.com/images/a b.jpg"),
            ("../images/./a b.jpg", "https://example.com/images/a b.jpg"),
            ("covers/../a%20b.jpg", "https://example.com/book/a%20b.jpg"),
            ("中文.jpg?x=a b#c d", "https://example.com/book/中文.jpg?x=a b#c d"),
            ("https://cdn.example.com/a b.jpg", "https://cdn.example.com/a b.jpg"),
            ("data:image/png;base64,A B", "data:image/png;base64,A B"),
            ("?x=a b", "https://example.com/book/?x=a b"),
            ("#a b", "https://example.com/book/1.html?old=1#a b"),
            ("", "https://example.com/book/1.html?old=1#old")
        ]
        for (path, expected) in cases {
            XCTAssertEqual(HtmlFormatter.formatKeepImg("<img src='\(path)'>", redirectUrl: base),
                           "<img src=\"\(expected)\">", path)
        }
    }

    // Kotlin AppPattern.kt:20、NetworkUtils.kt:179：data 中 VT/FF 不改变原串。
    func testDataImageVerticalTabAndFormFeed() {
        let base = URL(string: "https://example.com/book/1.html")!
        for control in ["\u{000b}", "\u{000c}"] {
            let path = "data:image/\(control)png;base64,A\(control)B"
            XCTAssertEqual(HtmlFormatter.formatKeepImg("<img src='\(path)'>", redirectUrl: base), "<img src=\"\(path)\">")
        }
    }

    // Kotlin HtmlFormatterTest.kt:34–54：每条黄金断言均检查实际值与执行状态。
    func testEightGoldenCases() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/Conformance/fixtures/golden/HtmlFormatterTest.json"))
        let cases = try JSONDecoder().decode([ConformanceCase].self, from: data)
        XCTAssertEqual(cases.count, 8)
        for result in ConformanceRunner.run(cases).results {
            XCTAssertEqual(result.status, .passed, result.id)
            XCTAssertEqual(result.actual, result.expected, result.id)
            print("\(result.id): \(result.status) \(result.detail)")
        }
    }

    // Kotlin HtmlFormatter.kt:20–50：ASCII 空白参与缩进，全角空格与 NBSP 保留。
    func testWhitespaceAndParagraphs() {
        XCTAssertEqual(HtmlFormatter.format(nil), "")
        XCTAssertEqual(HtmlFormatter.format(""), "")
        XCTAssertEqual(HtmlFormatter.format(" \t\r\n"), "　　　　")
        XCTAssertEqual(HtmlFormatter.format("<p>A</p><p>B</p>"), "　　　　A\n　　B\n　　")
        XCTAssertEqual(HtmlFormatter.formatIntro("　　A\n\u{00a0}B　"), "　　A\n\u{00a0}B　")
        XCTAssertEqual(HtmlFormatter.formatIntro("A\rB\\rC"), "A\rB\nC")
    }

    // Kotlin HtmlFormatter.kt:9–15、41–47：实体处理顺序、大小写及非贪婪误用的边界。
    func testMarkupAndEntities() {
        XCTAssertEqual(HtmlFormatter.formatIntro("A&nbsp;&nbsp;B&ensp;&emsp;C&thinsp;&zwnj;&zwj;\u{2009}\u{200c}\u{200d}&amp;"), "A B  C&amp;")
        XCTAssertEqual(HtmlFormatter.formatIntro("<P>A</P><p>B</p><h１>C</h１>"), "A\nB\n<h１>C</h１>")
        XCTAssertEqual(HtmlFormatter.formatIntro("A<!-- a > b -->B"), "A<!-- a > b -->B")
        XCTAssertEqual(HtmlFormatter.formatIntro("A<b\tx='1'>B</b>C"), "A<b\tx='1'>BC")
    }

    // Kotlin HtmlFormatter.kt:53–85；HtmlFormatterTest.kt:64–69：相对图片 URL 及保留尾部。
    func testKeepImagesAndBaseURL() {
        let base = URL(string: "https://example.com/books/chapters/1.html")!
        XCTAssertEqual(HtmlFormatter.formatKeepImg(nil, redirectUrl: base), "")
        XCTAssertEqual(HtmlFormatter.formatKeepImg("A<img src='../images/cover.jpg'>B", redirectUrl: base), "A<img src=\"https://example.com/books/images/cover.jpg\">B")
        XCTAssertEqual(HtmlFormatter.formatKeepImg("<img src=' x.jpg '>"), "<img src=\"x.jpg\">")
        XCTAssertEqual(HtmlFormatter.formatKeepImg("<img src='javascript:void(0)'>", redirectUrl: base), "<img src=\"\">")
        XCTAssertEqual(HtmlFormatter.formatKeepImg("<img src='data:image/png;base64,AA'>", redirectUrl: base), "<img src=\"data:image/png;base64,AA\">")
        XCTAssertEqual(HtmlFormatter.formatKeepImg("A<img alt='x'>B"), "A<img alt='x'>B")
        XCTAssertEqual(HtmlFormatter.formatKeepImg("<IMG SRC='x.jpg'>"), "")
    }

    // Kotlin HtmlFormatter.kt:16–18、67–74；AnalyzeUrl.kt:817：分支优先级与 JSON 参数。
    func testImageAttributePrecedenceAndParameters() {
        let base = URL(string: "https://example.com/book/1.html")!
        XCTAssertEqual(HtmlFormatter.formatKeepImg("<img src=\"fallback\" data-original='lazy'>"), "<img src=\"lazy\">")
        XCTAssertEqual(HtmlFormatter.formatKeepImg("<img data-any='custom'>"), "<img src=\"custom\">")
        XCTAssertEqual(HtmlFormatter.formatKeepImg("<img src=\"../a.jpg, {headers: {X: 1}}\" data-src='lazy'>", redirectUrl: base), "<img src=\"https://example.com/a.jpg,{headers: {X: 1}}\">")
        XCTAssertEqual(HtmlFormatter.formatKeepImg("<img\u{00a0}src='x'>"), "<img\u{00a0}src='x'>")
        XCTAssertEqual(HtmlFormatter.formatKeepImg("<img ſrc='x'>"), "<img ſrc='x'>")
        XCTAssertEqual(HtmlFormatter.formatKeepImg("<img SRC='x'>"), "<img src=\"x\">")
    }
}
