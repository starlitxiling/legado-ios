import XCTest

final class ReaderInterfaceUITests: XCTestCase {
    @MainActor
    func testStylesMarginsAndTitleInformation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-detail-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO", "-readStyleSelect", "0", "-textSize", "24", "-lineSpacingExtra", "10", "-letterSpacing", "0", "-shareLayout", "NO", "-doubleHorizontalPage", "0"]
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
        app.buttons.matching(identifier: "reader.style.2").firstMatch.tap()
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

    @MainActor
    func testConfiguredDoublePageAndTapBookmark() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-detail-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO", "-readStyleSelect", "0", "-textSize", "24", "-lineSpacingExtra", "10", "-letterSpacing", "0", "-shareLayout", "NO", "-doubleHorizontalPage", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 15))
        app.buttons["detail.read"].tap()
        XCTAssertTrue(app.otherElements["reader.body"].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["doubleHorizontalPage"].waitForExistence(timeout: 5))
        app.buttons["doubleHorizontalPage"].tap()
        app.buttons["双页"].tap()
        app.buttons["完成"].tap()
        snapshot(app, "u6-reader-menu")
        app.buttons["收起"].tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "reader.body").element(boundBy: 1).waitForExistence(timeout: 5))
        snapshot(app, "u6-reader-double-page")
        app.swipeLeft()
        let page = app.otherElements.matching(identifier: "reader.body").element(boundBy: 0)
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertEqual(page.value as? String, "第 1 章，第 3 页")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["设置"].tap()
        let zones = app.buttons["点击区域设置"]
        for _ in 0..<10 where !zones.isHittable { app.swipeUp() }
        XCTAssertTrue(zones.isHittable); zones.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "左上：")).firstMatch.tap()
        app.buttons["添加书签"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["完成"].tap()
        app.buttons["收起"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["更多"].tap()
        app.buttons["书签列表"].tap()
        XCTAssertTrue(app.navigationBars["书签"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["第一章 启航"].exists)
    }

    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
