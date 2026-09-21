import XCTest

final class SearchInterfaceUITests: XCTestCase {
    @MainActor
    func testInputHelpResultsFilterAndScope() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-search-gallery", "-reset-search-gallery"]
        app.launch()
        let history = app.buttons["search.history.Ocean"]
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        app.textFields["书名或作者"].typeText("Temp")
        app.navigationBars.buttons["清空"].tap()
        snapshot(app, name: "u3-input-help")
        history.tap()
        let first = app.buttons["search.result.Ocean Journey|A. Writer"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["已搜 2 / 2"].exists)
        snapshot(app, name: "u3-search-results")
        app.buttons["search.menu"].tap()
        app.buttons["搜索结果屏蔽词"].tap()
        let filter = app.textViews["search.filter.input"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap(); filter.typeText("Ocean")
        app.buttons["确定"].tap()
        XCTAssertFalse(first.exists)
        XCTAssertTrue(app.buttons["search.result.Mountain Stories|B. Writer"].exists)
        app.buttons["search.menu"].tap()
        app.buttons["多分组 / 书源"].tap()
        XCTAssertTrue(app.buttons["search.scope.group.History"].waitForExistence(timeout: 5))
        app.buttons["search.scope.group.History"].tap()
        app.buttons["确定"].tap()
        XCTAssertTrue(app.staticTexts["已搜 1 / 1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["search.result.Mountain Stories|B. Writer"].exists)
        app.terminate()
        app.launchArguments = ["-search-gallery"]
        app.launch()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 10))
        app.buttons["search.history.Ocean"].tap()
        XCTAssertTrue(app.staticTexts["已搜 1 / 1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["search.result.Ocean Journey|A. Writer"].exists)
    }

    @MainActor
    func testLongPressDeletesSingleHistoryKeyword() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-search-gallery", "-reset-search-gallery"]
        app.launch()
        let history = app.buttons["search.history.Adventure"]
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        history.press(forDuration: 0.8)
        XCTAssertTrue(history.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.history.Ocean"].exists)
    }

    @MainActor private func snapshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
