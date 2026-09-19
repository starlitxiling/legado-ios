import XCTest
@testable import LegadoCore

final class ChineseConverterTests: XCTestCase {
    func testPinnedOpenCCPhraseAndCharacterPairs() throws {
        let pairs = [
            ("头发", "頭髮"), ("理发", "理髮"), ("发展", "發展"), ("发现", "發現"),
            ("皇后", "皇后"), ("后来", "後來"), ("干杯", "乾杯"), ("干燥", "乾燥"),
            ("干净", "乾淨"), ("后台", "後臺"), ("里面", "裏面"), ("面条", "麪條"),
            ("面包", "麪包"), ("台湾", "臺灣"), ("数据库", "數據庫"), ("重复", "重複"),
            ("钟表", "鐘錶"), ("音乐", "音樂"), ("阅读", "閱讀"), ("书籍", "書籍")
        ]
        for (simplified, traditional) in pairs {
            XCTAssertEqual(try ChineseConverter.s2t(simplified), traditional, simplified)
            XCTAssertEqual(try ChineseConverter.t2s(traditional), simplified, traditional)
        }
    }

    func testLongestPhraseOverridesAmbiguousCharacterAndPreservesOtherScalars() throws {
        XCTAssertEqual(try ChineseConverter.s2t("皇后后来理发，发展头发。"), "皇后後來理髮，發展頭髮。")
        XCTAssertEqual(try ChineseConverter.s2t("后发"), "後發")
        let unchanged = "ASCII 123\n\t\u{1F600}e\u{301}"
        XCTAssertEqual(try ChineseConverter.t2s(unchanged), unchanged)
        XCTAssertEqual(try ChineseConverter.s2t(""), "")
        XCTAssertEqual(try ChineseConverter.convert("后", type: 0), "后")
        XCTAssertEqual(try ChineseConverter.convert("后", type: 99), "后")
    }

    func testJavaHostConversion() throws {
        let engine = JsEngine(httpClient: ReplayHttpClient())
        XCTAssertEqual(try engine.evaluateScript("java.s2t('头发') + '|' + java.t2s('後來')") as? String, "頭髮|后来")
    }

    func testTitleConvertsBeforeReplacementAndContentUsesSameSetting() throws {
        var book = Book(); book.name = "Book"; book.bookUrl = "book"
        var chapter = BookChapter(); chapter.title = "头发"; chapter.url = "chapter"
        var rule = ReplaceRule(); rule.id = 1; rule.pattern = "頭髮"; rule.replacement = "髮型"
        rule.scopeTitle = true; rule.scopeContent = true
        let processor = ContentProcessor(rules: [rule], chineseConverterType: 2)
        XCTAssertEqual(try processor.title(book: book, chapter: chapter), "髮型")
        XCTAssertEqual(try processor.getContent(book: book, chapter: chapter, content: "头发\n后来发展头发").text,
            "髮型\n　　後來發展髮型")
        XCTAssertEqual(try processor.title(book: book, chapter: chapter, useReplace: false), "頭髮")
    }
}
