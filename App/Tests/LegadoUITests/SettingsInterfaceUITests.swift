import XCTest

final class SettingsInterfaceUITests: XCTestCase {
    @MainActor
    func testSettingsNavigationAndTaskExecution() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-settings-gallery", "-autoTaskService", "NO", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO", "-themeMode", "0"]
        app.launch()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 20))
        capture(app, "u8-my")
        app.staticTexts["定时任务"].tap()
        XCTAssertTrue(app.staticTexts["示例任务"].waitForExistence(timeout: 5))
        app.buttons["编辑"].tap()
        XCTAssertTrue(app.textFields["名称"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["名称"].value as? String, "示例任务")
        app.buttons["取消"].tap()
        app.buttons["立即运行"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Task completed")).firstMatch.waitForExistence(timeout: 10))
        capture(app, "u8-tasks")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open(app, "主题设置")
        XCTAssertTrue(app.staticTexts["切换图标"].waitForExistence(timeout: 5))
        capture(app, "u8-theme")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open(app, "其它设置")
        XCTAssertTrue(app.switches["显示发现"].waitForExistence(timeout: 5))
        capture(app, "u8-other")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open(app, "备份与恢复")
        XCTAssertTrue(app.textFields["服务器地址"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["服务器地址"].value as? String, "服务器地址")
        capture(app, "u8-backup")
    }
    @MainActor private func open(_ app: XCUIApplication, _ title: String) {
        let row = app.staticTexts[title].firstMatch
        for _ in 0..<5 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable); row.tap()
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
