import XCTest
import UIKit

final class ExploreInterfaceUITests: XCTestCase {
    @MainActor
    func testAccordionControlsFilterAndBookListTabs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-explore-gallery"]
        app.launch()
        let first = app.buttons["explore.source.https://explore1.test"]
        let second = app.buttons["explore.source.https://explore2.test"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        first.tap()
        XCTAssertTrue(app.buttons["explore.kind.Popular"].waitForExistence(timeout: 5))
        let input = app.textFields["explore.input.Query"]
        XCTAssertTrue(input.exists)
        app.buttons["explore.control.Mode"].tap()
        XCTAssertTrue(app.buttons["explore.control.Mode"].label.contains("Finished"))
        app.buttons["explore.control.Apply"].tap()
        XCTAssertTrue(app.buttons["explore.kind.Popular"].waitForExistence(timeout: 5))
        second.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "explore.kind.Popular").count, 1)
        snapshot(app, name: "u4-explore-controls")
        app.buttons["explore.kind.Popular"].tap()
        XCTAssertTrue(app.staticTexts["Sample Discovery Book"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["explore.tab.New"].exists)
        app.buttons["explore.tab.New"].tap()
        XCTAssertTrue(app.navigationBars["New"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已加载全部书籍"].waitForExistence(timeout: 5))
        assertVisibleText(app.buttons["explore.tab.New"])
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "u4-booklist-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        snapshot(app, name: "u4-explore-books")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["explore.groups"].tap()
        app.buttons["Other"].tap()
        XCTAssertTrue(app.buttons["explore.source.https://explore3.test"].waitForExistence(timeout: 5))
        XCTAssertFalse(first.exists)
    }

    @MainActor private func assertVisibleText(_ element: XCUIElement) {
        guard let image = UIImage(data: element.screenshot().pngRepresentation)?.cgImage else {
            XCTFail("Missing rendered tab image"); return
        }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var dark = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            if pixels[offset + 3] > 200 && (red + green + blue) / 3 < 150 { dark += 1 }
        }
        XCTAssertGreaterThan(dark, 8, "The tab is accessible but its text is visually clipped")
    }

    @MainActor private func snapshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
