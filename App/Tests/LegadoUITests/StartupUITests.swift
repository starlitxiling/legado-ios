import XCTest

final class StartupUITests: XCTestCase {
    @MainActor
    func testColdLaunchReachesInteractiveBookshelf() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20),
                      "App must leave the database loading screen and display the main tabs")
        XCTAssertFalse(app.staticTexts["正在打开书库"].exists)
        XCTAssertTrue(app.navigationBars["书架"].exists)
        openSettings(app)
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testThemePresetsAndEInkRemainInteractive() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        openSettings(app)
        let themeSettings = app.staticTexts["主题设置"]
        if !themeSettings.isHittable { app.swipeUp() }
        XCTAssertTrue(themeSettings.waitForExistence(timeout: 5))
        themeSettings.tap()
        app.staticTexts["主题列表"].tap()
        for name in ["默认", "典雅蓝", "黑白", "A屏黑"] {
            let preset = app.buttons[name]
            XCTAssertTrue(preset.waitForExistence(timeout: 5))
            preset.tap()
            XCTAssertTrue(app.navigationBars["主题列表"].exists)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "theme-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.buttons["默认"].tap()
        app.navigationBars["主题列表"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["主题设置"].waitForExistence(timeout: 5))
        app.buttons["theme.mode"].tap()
        XCTAssertTrue(app.buttons["墨水屏"].waitForExistence(timeout: 5))
        app.buttons["墨水屏"].tap()
        XCTAssertTrue(app.navigationBars["主题设置"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "theme-eink"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["theme.mode"].tap()
        app.buttons["跟随系统"].tap()
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let settings = app.tabBars.buttons["设置"]
        if settings.exists {
            settings.tap()
        } else {
            app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1).tap()
            let settingsRow = app.tables.staticTexts["设置"]
            XCTAssertTrue(settingsRow.waitForExistence(timeout: 5))
            settingsRow.tap()
        }
    }

}
