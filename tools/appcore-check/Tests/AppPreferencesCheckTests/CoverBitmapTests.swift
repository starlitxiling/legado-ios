import XCTest
import CoreGraphics
import ImageIO
@testable import SettingsBackupCheck

final class CoverBitmapTests: XCTestCase {
    func testDownsamplingURLCacheAndDisabledCache() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1600, height: 2400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 2400))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let cache = CoverBitmapCache()
        let first = await cache.image(data as Data, key: "https://example.test/cover", maximumPixels: 180, maximumMegabytes: 4)
        let image = try XCTUnwrap(first)
        XCTAssertEqual(image.height, 180); XCTAssertEqual(image.width, 120)
        let cached = await cache.image(Data(), key: "https://example.test/cover", maximumPixels: 180, maximumMegabytes: 4)
        XCTAssertTrue(image === cached)
        let invalid = await cache.image(Data(), key: "https://example.test/other", maximumPixels: 180, maximumMegabytes: 4)
        XCTAssertNil(invalid)
        let uncached = await cache.image(data as Data, key: "https://example.test/cover", maximumPixels: 90, maximumMegabytes: 0)
        XCTAssertEqual(uncached?.height, 90)
        let removed = await cache.image(Data(), key: "https://example.test/cover", maximumPixels: 180, maximumMegabytes: 0)
        XCTAssertNil(removed)
    }
}
