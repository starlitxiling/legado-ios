import XCTest
import CoreGraphics
@testable import SettingsBackupCheck

final class EInkImageProcessorTests: XCTestCase {
    private func gradient(width: Int = 64, height: Int = 32, alpha: Bool = false) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for x in 0..<width {
            let level = CGFloat(x) / CGFloat(width - 1)
            context.setFillColor(red: level, green: level * 0.5, blue: 1 - level, alpha: alpha ? 0 : 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func values(_ image: CGImage) throws -> [UInt8] {
        XCTAssertEqual(image.bitsPerPixel, 8)
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        return Array(data.prefix(image.bytesPerRow * image.height))
    }

    func testModesProduceOnlyTheirGrayLevels() throws {
        let source = try gradient()
        let gray = try values(try XCTUnwrap(EInkImageProcessor.process(source, mode: .gray, threshold: 128)))
        XCTAssertGreaterThan(Set(gray).count, 16)
        let levels = Set(try values(try XCTUnwrap(EInkImageProcessor.process(source, mode: .levels, threshold: 128))))
        XCTAssertTrue(levels.allSatisfy { $0 % 17 == 0 }, "\(levels.sorted())")
        XCTAssertLessThanOrEqual(levels.count, 16)
        let dithered = try values(try XCTUnwrap(EInkImageProcessor.process(source, mode: .dither, threshold: 128)))
        XCTAssertEqual(Set(dithered), [0, 255])
        let threshold = try values(try XCTUnwrap(EInkImageProcessor.process(source, mode: .threshold, threshold: 128)))
        XCTAssertEqual(Set(threshold), [0, 255])
        let mean = { (pixels: [UInt8]) in Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count) }
        XCTAssertEqual(mean(dithered), mean(gray), accuracy: 12)
        let lighter = try values(try XCTUnwrap(EInkImageProcessor.process(source, mode: .threshold, threshold: 30)))
        XCTAssertGreaterThan(lighter.filter { $0 == 255 }.count, threshold.filter { $0 == 255 }.count)
    }

    func testTransparentPixelsBecomePaperWhiteAndOversizedImagesAreSkipped() throws {
        let clear = try values(try XCTUnwrap(EInkImageProcessor.process(try gradient(alpha: true), mode: .dither, threshold: 128)))
        XCTAssertEqual(Set(clear), [255])
        let huge = try XCTUnwrap(CGContext(data: nil, width: 2001, height: 2000, bitsPerComponent: 8, bytesPerRow: 2001,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage())
        XCTAssertNil(EInkImageProcessor.process(huge, mode: .gray, threshold: 128))
    }
}
