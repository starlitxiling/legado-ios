import XCTest
import CoreText
import LegadoCore
@testable import ReaderCheck

final class ReaderTypographyTests: XCTestCase {
    func testSplitChapterNumberPreservesBodyOffsetsAndStyle() throws {
        var settings = ReaderSettings(); settings.configuration.splitChapterTitle = true
        settings.configuration.titleNumberSize = 6; settings.configuration.titleNumberColor = -65536
        let value = try Paginator().paginate(title: "第一卷 第二章 启航", paragraphs: ["Body"], size: CGSize(width: 300, height: 600), settings: settings)
        XCTAssertEqual(value.text.string, "第一卷 第二章\n启航\nBody")
        XCTAssertEqual(value.titleLength, ("第一卷 第二章\n启航\n" as NSString).length)
        let font = value.text.attribute(.init(kCTFontAttributeName as String), at: 0, effectiveRange: nil) as! CTFont
        XCTAssertEqual(CTFontGetSize(font), settings.textSize + 6)
        let unchanged = try Paginator().paginate(title: "Chapter One", paragraphs: ["Body"], size: CGSize(width: 300, height: 600), settings: settings)
        XCTAssertEqual(unchanged.text.string, "Chapter One\nBody")
    }

    func testTipCodesPreserveAndroidBackupValues() {
        let values = ReaderInfoValues(bookName: "Book", chapterTitle: "Chapter", time: "12:34", battery: 45,
                                      page: "2", totalPages: "10", readProgress: "20%", chapter: "3", totalChapters: "15")
        XCTAssertEqual(ReaderInfo.parts(code: 7, values: values), [.text("Book")])
        XCTAssertEqual(ReaderInfo.parts(code: 1, values: values), [.text("Chapter")])
        XCTAssertEqual(ReaderInfo.parts(code: 6, values: values), [.text("2/10  20%")])
        XCTAssertEqual(ReaderInfo.parts(code: 11, values: values), [.text("3/15")])
        XCTAssertEqual(ReaderInfo.parts(code: 8, values: values), [.text("12:34  "), .battery(45, false)])
        XCTAssertEqual(ReaderInfo.parts(code: 7, template: "", values: values), [])
        XCTAssertEqual(ReaderInfo.parts(code: 7, template: "{{书名}} {未知} {书名}", values: values), [.text("{{书名}} {未知} Book")])
    }

    func testConfiguredColorTrackingAndParagraphAlignmentReachCoreText() throws {
        var settings = ReaderSettings()
        settings.configuration.textColor = "#123456"; settings.letterSpacing = 0.25
        settings.textSize = 20; settings.textFullJustify = true
        let value = try Paginator().paginate(title: "", paragraphs: ["Some example body text"], size: CGSize(width: 300, height: 600), settings: settings)
        let attributes = value.text.attributes(at: 0, effectiveRange: nil)
        let color = attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] as! CGColor
        XCTAssertEqual(color.components![0], 18.0 / 255, accuracy: 0.001)
        XCTAssertEqual(attributes[NSAttributedString.Key(kCTKernAttributeName as String)] as? Double, 5)
        let style = attributes[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] as! CTParagraphStyle
        var alignment = CTTextAlignment.left
        XCTAssertTrue(CTParagraphStyleGetValueForSpecifier(style, .alignment, MemoryLayout<CTTextAlignment>.size, &alignment))
        XCTAssertEqual(alignment, .justified)
    }

    func testKotlinPunctuationTrimmingAvoidsGlyphOverlap() {
        XCTAssertEqual(ReaderPunctuation.trim(width: 40, em: 40, left: 4, right: 24).width, 20)
        XCTAssertEqual(ReaderPunctuation.trim(width: 40, em: 40, left: 24, right: 4).offset, -20)
        XCTAssertEqual(ReaderPunctuation.trim(width: 40, em: 40, left: 12, right: 12).offset, -10)
        XCTAssertEqual(ReaderPunctuation.trim(width: 15, em: 40, left: 8, right: 5).width, 0)
        XCTAssertEqual(ReaderPunctuation.targets("a\u{3002}\u{201c}b", mode: "adjacent"), [1, 2])
        XCTAssertEqual(ReaderPunctuation.targets("\u{201c}a\u{201d}", mode: "adjacent"), [])
        XCTAssertEqual(ReaderPunctuation.targets("\u{3002}\u{fe00}", mode: "all"), [])
    }

    func testBottomAlignmentDistributesOnlyFullPageLines() throws {
        var settings = ReaderSettings(); settings.textBottomJustify = true
        let value = try Paginator().paginate(title: "", paragraphs: [String(repeating: "Body text ", count: 200)], size: CGSize(width: 250, height: 300), settings: settings)
        let first = try XCTUnwrap(value.pages.first)
        XCTAssertGreaterThan(first.lines.count, 1)
        var descent: CGFloat = 0
        _ = CTLineGetTypographicBounds(first.lines.last!, nil, &descent, nil)
        XCTAssertEqual(first.lineOrigins.last!.y, descent, accuracy: 0.1)
        let last = try XCTUnwrap(value.pages.last)
        if last.lines.count > 1 { XCTAssertGreaterThan(last.lineOrigins.last!.y, descent) }
    }

    func testLineSpacingUsesKotlinTenthsOfFontHeight() throws {
        var settings = ReaderSettings(); settings.textSize = 20
        func gap(_ extra: Double) throws -> CGFloat {
            settings.lineSpacingExtra = extra
            let value = try Paginator().paginate(title: "", paragraphs: [String(repeating: "Body text ", count: 30)], size: CGSize(width: 250, height: 600), settings: settings)
            let frame = try XCTUnwrap(value.pages.first?.frame)
            var origins = [CGPoint](repeating: .zero, count: 2)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 2), &origins)
            return origins[0].y - origins[1].y
        }
        XCTAssertEqual(try gap(20), try gap(10) * 2, accuracy: 0.1)
    }
}
