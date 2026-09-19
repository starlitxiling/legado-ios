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
        let settings = app.tabBars.buttons["设置"]
        if settings.exists {
            settings.tap()
        } else {
            app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1).tap()
            let settingsRow = app.tables.staticTexts["设置"]
            XCTAssertTrue(settingsRow.waitForExistence(timeout: 5))
            settingsRow.tap()
        }
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
    }
}
