import XCTest

/// Screenshot walk-through of the e-ink theme; attachments are kept for visual review.
final class EInkAuditUITests: XCTestCase {
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "eink-" + name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    func testReaderWalkThrough() {
        let app = XCUIApplication()
        app.launchArguments = ["-detail-gallery", "-themeMode", "3", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO",
                               "-doubleHorizontalPage", "0", "-eInkRefreshInterval", "3"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 15))
        shot(app, "01-detail")
        app.buttons["detail.read"].tap()
        let body = app.otherElements.matching(identifier: "reader.body").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        sleep(1); shot(app, "02-reader")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.3)
        shot(app, "03-dragging")
        sleep(1); shot(app, "04-after-turn")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); shot(app, "05-turn3-flash")
        sleep(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1); shot(app, "06-menu")
        if app.buttons["界面"].exists { app.buttons["界面"].tap(); sleep(1); shot(app, "07-interface"); app.swipeDown(); sleep(1) }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); sleep(1)
        if app.buttons["更多"].exists { app.buttons["更多"].tap(); sleep(1); shot(app, "08-more") }
    }

    @MainActor
    func testMainScreensWalkThrough() {
        let app = XCUIApplication()
        app.launchArguments = ["-themeMode", "3", "-autoTaskService", "NO", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO",
                               "-showDiscovery", "YES", "-showRss", "YES", "-defaultHomePage", "bookshelf"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        sleep(1); shot(app, "10-bookshelf")
        app.tabBars.buttons["发现"].tap(); sleep(1); shot(app, "11-explore")
        app.tabBars.buttons["我的"].tap(); sleep(1); shot(app, "12-mine")
        if app.staticTexts["书源管理"].exists { app.staticTexts["书源管理"].tap(); sleep(1); shot(app, "13-sources"); app.navigationBars.buttons.element(boundBy: 0).tap() }
        app.swipeUp(); sleep(1); shot(app, "14-mine-bottom")
    }
}
