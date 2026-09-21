import XCTest

final class SourceInterfaceUITests: XCTestCase {
    @MainActor func testListSelectionAndEditorTabs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-source-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO", "-showSourceCheckState", "YES", "-sourceGroupByDomain", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["编辑 示例书源 1"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["书架使用 1"].exists)
        snapshot(app, "u7-sources")
        app.buttons["多选"].tap()
        XCTAssertTrue(app.buttons["全选"].waitForExistence(timeout: 5))
        app.buttons["全选"].tap()
        XCTAssertTrue(app.staticTexts["已选 3"].exists)
        app.buttons["完成"].tap()
        app.buttons["编辑 示例书源 1"].tap()
        XCTAssertTrue(app.buttons["source.tab.段评"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["source.field.bookSourceUrl"].value as? String, "https://source1.test")
        XCTAssertEqual(app.textViews["source.field.bookSourceName"].value as? String, "示例书源 1")
        snapshot(app, "u7-source-editor")
        app.buttons["source.tab.正文"].tap()
        XCTAssertTrue(app.textViews["source.field.ruleContent.content"].waitForExistence(timeout: 5))
        app.textViews["source.field.ruleContent.content"].tap()
        XCTAssertTrue(app.buttons["@css:"].waitForExistence(timeout: 5))
        app.buttons["@css:"].tap()
        XCTAssertEqual(app.textViews["source.field.ruleContent.content"].value as? String, "@css:")
        snapshot(app, "u7-source-keyboard")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["编辑 示例书源 1"].waitForExistence(timeout: 5))
        app.buttons["更多 示例书源 1"].tap()
        app.buttons["调试"].tap()
        XCTAssertTrue(app.buttons["开始调试"].waitForExistence(timeout: 5))
        app.textFields["书名、URL 或发现"].tap()
        XCTAssertTrue(app.staticTexts["书名：输入书名调试搜索"].waitForExistence(timeout: 5))
        snapshot(app, "u7-source-debug")
    }
    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
