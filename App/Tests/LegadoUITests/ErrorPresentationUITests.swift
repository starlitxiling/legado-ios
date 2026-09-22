import XCTest

final class ErrorPresentationUITests: XCTestCase {
    @MainActor
    func testChineseErrorBannerActionsAndSystemFilePicker() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-error-gallery", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.staticTexts["加载正文失败"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "测试书籍")).firstMatch.exists)
        XCTAssertTrue(app.buttons["error.dismiss"].exists)
        app.buttons["error.retry"].tap()
        XCTAssertTrue(app.staticTexts["重试次数：1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["加载正文失败"].exists)
        app.buttons["选择文件"].tap()
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "a4a-chinese-file-picker"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["选择文件"].waitForExistence(timeout: 5))
    }
}
