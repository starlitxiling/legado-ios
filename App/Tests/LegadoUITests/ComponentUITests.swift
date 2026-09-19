import XCTest

final class ComponentUITests: XCTestCase {
    @MainActor
    func testSearchSelectionAndEInkComponents() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-component-gallery"]
        app.launch()
        let search = app.textFields["搜索组件"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("hello\n")
        XCTAssertTrue(app.staticTexts["gallery.message"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["gallery.message"].label, "hello")
        app.buttons["清空"].tap()
        XCTAssertEqual(search.value as? String, "搜索组件")
        app.buttons["全选"].tap()
        XCTAssertTrue(app.buttons["导出"].isEnabled)
        XCTAssertTrue(app.staticTexts["已选 3"].exists)
        for name in ["components", "components-eink"] {
            if name.hasSuffix("eink") { app.buttons["墨水屏"].tap() }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.buttons["跟随系统"].tap()
    }
}
