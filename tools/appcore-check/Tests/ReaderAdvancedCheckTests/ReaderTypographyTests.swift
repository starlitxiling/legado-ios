import XCTest
import CoreText
import LegadoCore
@testable import ReaderCheck

final class ReaderTypographyTests: XCTestCase {
    func testUnderlineDoesNotRestartDashesAtCoreTextRunBoundaries() throws {
        let text = NSMutableAttributedString(string: "Underline", attributes: ReaderTypography.bodyAttributes(ReaderSettings(), fontName: "Helvetica"))
        let line = CTLineCreateWithAttributedString(text)
        text.addAttribute(NSAttributedString.Key("test.segment"), value: 1, range: NSRange(location: 2, length: 3))
        let segmented = CTLineCreateWithAttributedString(text)
        func render(_ line: CTLine) throws -> Data {
            let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 80, bitsPerComponent: 8, bytesPerRow: 800,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            var config = ReadBookConfig(); config.underlineMode = 6
            ReaderUnderline.draw(line: line, origin: CGPoint(x: 10, y: 40), title: false, config: config, context: context)
            return Data(bytes: try XCTUnwrap(context.data), count: 64000)
        }
        XCTAssertEqual(try render(line), try render(segmented))
    }

    func testUnderlineStartsAfterParagraphIndent() throws {
        let attributes = ReaderTypography.bodyAttributes(ReaderSettings(), fontName: "Helvetica")
        func leftmost(_ string: String) throws -> Int {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
            let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 80, bitsPerComponent: 8, bytesPerRow: 800,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            var config = ReadBookConfig(); config.underlineMode = 1; config.underlineColorSet = true; config.underlineColor = -65536
            ReaderUnderline.draw(line: line, origin: CGPoint(x: 10, y: 40), title: false, config: config, context: context,
                                 text: string as NSString)
            let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            for x in 0..<200 { for y in 0..<80 where bytes[y * 800 + x * 4 + 3] > 0 { return x } }
            return -1
        }
        let plain = try leftmost("Underline")
        let indented = try leftmost("\u{3000}\u{3000}Underline")
        XCTAssertGreaterThanOrEqual(plain, 9)
        XCTAssertGreaterThan(indented, plain + 10)
    }

    func testUnderlineModesDrawAndRespectTitleAndBodySwitches() throws {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Underline", attributes:
            ReaderTypography.bodyAttributes(ReaderSettings(), fontName: "Helvetica")))
        func bitmap(_ mode: Int, title: Bool = false, enabled: Bool = true) throws -> Data {
            var config = ReadBookConfig(); config.underlineMode = mode
            config.underlineBodyEnabled = enabled; config.underlineTitleEnabled = enabled
            config.underlineColorSet = true; config.underlineColor = -65536
            let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 80, bitsPerComponent: 8, bytesPerRow: 800,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ReaderUnderline.draw(line: line, origin: CGPoint(x: 10, y: 40), title: title, config: config, context: context)
            return Data(bytes: try XCTUnwrap(context.data), count: 64000)
        }
        let blank = try bitmap(0)
        var rendered = Set<Data>()
        for mode in 1...6 {
            let image = try bitmap(mode)
            XCTAssertNotEqual(image, blank)
            rendered.insert(image)
            XCTAssertEqual(try bitmap(mode, enabled: false), blank)
            XCTAssertEqual(try bitmap(mode, title: true, enabled: false), blank)
        }
        XCTAssertEqual(rendered.count, 6)
    }

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
