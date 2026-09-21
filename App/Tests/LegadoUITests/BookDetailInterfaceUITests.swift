import XCTest

final class BookDetailInterfaceUITests: XCTestCase {
    @MainActor
    func testDetailsEditorsAndDirectReading() {
        continueAfterFailure = false
        let app = launch()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["林舟"].exists)
        snapshot(app, "u5-book-detail")
        app.buttons["detail.intro.toggle"].tap()
        XCTAssertEqual(app.buttons["detail.intro.toggle"].label, "收起")
        app.buttons["detail.intro.toggle"].tap()
        app.buttons["设置分组"].tap()
        XCTAssertTrue(app.switches["科幻"].waitForExistence(timeout: 5))
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        app.buttons["更多"].tap()
        app.buttons["生成更新任务"].tap()
        XCTAssertTrue(app.navigationBars["更新任务"].waitForExistence(timeout: 5))
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 5))
        app.buttons["detail.read"].tap()
        XCTAssertTrue(app.staticTexts["第一章 启航"].waitForExistence(timeout: 15))
        snapshot(app, "u5-detail-reading")
    }

    @MainActor
    func testSourceSwitchAndValidation() {
        continueAfterFailure = false
        let app = launch()
        XCTAssertTrue(app.buttons["换源"].waitForExistence(timeout: 15))
        app.buttons["换源"].tap()
        XCTAssertTrue(app.staticTexts["示例书源 2"].waitForExistence(timeout: 10))
        snapshot(app, "u5-source-switch")
        app.buttons.matching(identifier: "校验").element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "校验通过")).firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["示例书源 2"].tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["示例书源 2"].exists)
    }

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-detail-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO"]
        app.launch()
        return app
    }

    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
