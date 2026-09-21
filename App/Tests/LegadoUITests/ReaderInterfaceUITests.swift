import XCTest

final class ReaderInterfaceUITests: XCTestCase {
    @MainActor
    func testStylesMarginsAndTitleInformation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-detail-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 15))
        app.buttons["detail.read"].tap()
        let body = app.otherElements["reader.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["界面"].waitForExistence(timeout: 5))
        app.buttons["界面"].tap()
        XCTAssertTrue(app.sliders["字号"].waitForExistence(timeout: 5))
        snapshot(app, "u6-reader-interface")
        app.sliders["字号"].adjust(toNormalizedSliderPosition: 0.42)
        app.buttons["预设2"].tap()
        app.buttons["边距"].tap()
        XCTAssertTrue(app.switches["左右边距联动"].waitForExistence(timeout: 5))
        app.sliders.matching(identifier: "左").element(boundBy: 0).adjust(toNormalizedSliderPosition: 0.3)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["信息"].tap()
        XCTAssertTrue(app.navigationBars["信息与标题"].waitForExistence(timeout: 5))
        snapshot(app, "u6-reader-information")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["界面"].waitForExistence(timeout: 5))
        app.buttons["收起"].tap()
        snapshot(app, "u6-reader-typography")
    }

    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
