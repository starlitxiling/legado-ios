import XCTest
import UIKit
@testable import Legado

@MainActor
final class ReaderBackgroundImageTests: XCTestCase {
    func testBackgroundDecodeIsSharedAndBoundedAndImportIsDownsampled() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let large = UIGraphicsImageRenderer(size: CGSize(width: 4096, height: 2048), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4096, height: 2048))
        }
        let data = try XCTUnwrap(large.jpegData(compressionQuality: 0.8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let store = ReaderBackgroundImageStore()
        async let first = store.image(at: url, maximumPixelSize: 1024)
        async let second = store.image(at: url, maximumPixelSize: 1024)
        let images = try await [first, second]
        XCTAssertTrue(images[0] === images[1])
        XCTAssertLessThanOrEqual(try XCTUnwrap(images[0].cgImage).width, 1024)
        let exported = try ReaderBackgroundImageStore.importedJPEG(data, maximumPixelSize: 1024)
        let decoded = try XCTUnwrap(UIImage(data: exported)?.cgImage)
        XCTAssertLessThanOrEqual(decoded.width, 1024)
        XCTAssertLessThanOrEqual(decoded.height, 1024)
    }
}
