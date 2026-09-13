import XCTest
import CoreGraphics
import ImageIO
@testable import IconRenderer

final class IconRendererTests: XCTestCase {
    let resources = Bundle.module.url(forResource: "res", withExtension: nil, subdirectory: "Fixtures")!

    func testRelativeAndRepeatedCommands() throws {
        let path = try SVGPath.parse("m10 10 10 0 h10 v20 l-20 0 z")
        XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 10, y: 10, width: 20, height: 20))
        XCTAssertEqual(path.currentPoint, CGPoint(x: 10, y: 10))
    }

    func testCurvesAndReflections() throws {
        let path = try SVGPath.parse("M0 0 C0 10 10 10 10 0 s10 -10 10 0 Q25 10 30 0 t10 0")
        XCTAssertEqual(path.currentPoint, CGPoint(x: 40, y: 0))
        XCTAssertEqual(path.boundingBoxOfPath.minY, -7.5, accuracy: 0.001)
        XCTAssertEqual(path.boundingBoxOfPath.maxY, 7.5, accuracy: 0.001)
    }

    func testArcs() throws {
        let path = try SVGPath.parse("M10 0 A10 10 0 0 1 0 10 a10 10 0 0 1 -10 -10")
        XCTAssertEqual(path.currentPoint.x, -10, accuracy: 0.001)
        XCTAssertEqual(path.boundingBoxOfPath.maxY, 10, accuracy: 0.001)
        XCTAssertTrue(path.contains(CGPoint(x: 0, y: 5)))
    }

    func testCompactSyntaxAndDegenerateArcs() throws {
        let compact = try SVGPath.parse("M1e1 0A10 10 0 010 10ZM2 2l.5-.5")
        XCTAssertEqual(compact.currentPoint, CGPoint(x: 2.5, y: 1.5))
        let corrected = try SVGPath.parse("M0 0a1 1 0 0 1 20 0")
        XCTAssertEqual(corrected.boundingBoxOfPath.minY, -10, accuracy: 0.001)
        let degenerate = try SVGPath.parse("M0 0A0 3 45 1 0 10 10a3 3 0 1 1 0 0")
        XCTAssertEqual(degenerate.currentPoint, CGPoint(x: 10, y: 10))
        XCTAssertEqual(degenerate.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    func testInvalidPathFails() {
        for data in ["M0", "M0 0 X1 2", "L0 0", "M0 0 A1 1 0 2 0 3 4", "M0 0 Z 1"] {
            XCTAssertThrowsError(try SVGPath.parse(data), data)
        }
    }

    func testVectorPixelsAndGroupClip() throws {
        let xml = """
        <vector xmlns:android="http://schemas.android.com/apk/res/android" android:viewportWidth="10" android:viewportHeight="10">
          <path android:pathData="M0 0H10V10H0Z" android:fillColor="#fff"/>
          <group android:translateX="2" android:translateY="2" android:pivotX="1" android:pivotY="1" android:rotation="90" android:scaleX="2">
            <clip-path android:pathData="M0 0H2V2H0Z"/>
            <path android:pathData="M-10 -10H10V10H-10Z" android:fillColor="#f00" android:fillAlpha="0.5"/>
          </group>
        </vector>
        """
        let image = try IconRenderer(resources: resources).render(vector: Data(xml.utf8), size: 10)
        let bytes = image.dataProvider!.data! as Data
        let center = 3 * image.bytesPerRow + 3 * 4
        XCTAssertEqual(bytes[center], 255)
        XCTAssertEqual(Int(bytes[center + 1]), 127, accuracy: 1)
        XCTAssertEqual(bytes[0], 255)
        XCTAssertEqual(bytes[1], 255)
    }

    func testSixIconsAreOpaqueAndSized() throws {
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/test-icons")
        defer { try? FileManager.default.removeItem(at: output) }
        try IconRenderer(resources: resources).generate(to: output)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).count, 12)
        for number in 1...6 {
            for (scale, size) in [(2, 120), (3, 180)] {
                let url = output.appendingPathComponent("launcher\(number)@\(scale)x.png")
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                XCTAssertEqual(image.width, size)
                XCTAssertEqual(image.height, size)
                XCTAssertTrue([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo))
            }
        }
    }
}
