import XCTest
import CoreText
import LegadoCore
@testable import ReaderCheck

final class EInkReaderTests: XCTestCase {
    private func eInkSettings(_ change: (inout EInkSettings) -> Void = { _ in }) -> ReaderSettings {
        var settings = ReaderSettings(); settings.isEInk = true
        var eInk = EInkSettings(); change(&eInk); settings.eInk = eInk
        return settings
    }

    func testPaperOverridesOnlySolidEInkBackgrounds() {
        var settings = eInkSettings { $0.paper = .warm }
        settings.configuration.bgTypeEInk = 0; settings.configuration.bgStrEInk = "#FFFFFF"
        XCTAssertEqual(settings.backgroundValue, ARGBColor(0xFFEDE6D6).hex)
        settings.eInk?.paper = .style
        XCTAssertEqual(settings.backgroundValue, "#FFFFFF")
        settings.eInk?.paper = .white
        settings.configuration.bgTypeEInk = 1; settings.configuration.bgStrEInk = "羊皮纸1.jpg"
        XCTAssertEqual(settings.backgroundValue, "羊皮纸1.jpg")
        settings.isEInk = false
        settings.configuration.bgStr = "#123456"
        XCTAssertEqual(settings.backgroundValue, "#123456")
    }

    func testDarkenedTextAddsStrokeOnlyInEInk() throws {
        let darker = ReaderTypography.bodyAttributes(eInkSettings { $0.textWeight = 2 }, fontName: "Helvetica")
        XCTAssertEqual(darker[.init(kCTStrokeWidthAttributeName as String)] as? Double, -5)
        XCTAssertNotNil(darker[.init(kCTStrokeColorAttributeName as String)])
        XCTAssertNotNil(ReaderTypography.titleAttributes(eInkSettings(), bodyFontName: "Helvetica")[.init(kCTStrokeWidthAttributeName as String)])
        XCTAssertNil(ReaderTypography.bodyAttributes(eInkSettings { $0.textWeight = 0 }, fontName: "Helvetica")[.init(kCTStrokeWidthAttributeName as String)])
        var plain = eInkSettings { $0.textWeight = 2 }; plain.isEInk = false
        XCTAssertNil(ReaderTypography.bodyAttributes(plain, fontName: "Helvetica")[.init(kCTStrokeWidthAttributeName as String)])

        func inkPixels(_ settings: ReaderSettings) throws -> Int {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "阅读墨水屏", attributes:
                ReaderTypography.bodyAttributes(settings, fontName: "Helvetica")))
            let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 60, bitsPerComponent: 8, bytesPerRow: 960,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.textPosition = CGPoint(x: 4, y: 18); CTLineDraw(line, context)
            let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            return (0..<(240 * 60)).filter { bytes[$0 * 4 + 3] > 128 }.count
        }
        XCTAssertGreaterThan(try inkPixels(eInkSettings { $0.textWeight = 2 }), try inkPixels(eInkSettings { $0.textWeight = 0 }))
    }

    func testEInkHidesStatusBarWithoutChangingSavedPreference() {
        var settings = eInkSettings()
        XCTAssertFalse(settings.hideStatusBar)
        XCTAssertTrue(settings.hidesStatusBar)
        settings.eInk?.hideStatusBar = false
        XCTAssertFalse(settings.hidesStatusBar)
        settings.isEInk = false; settings.eInk?.hideStatusBar = true
        XCTAssertFalse(settings.hidesStatusBar)
        settings.hideStatusBar = true
        XCTAssertTrue(settings.hidesStatusBar)
    }
}
