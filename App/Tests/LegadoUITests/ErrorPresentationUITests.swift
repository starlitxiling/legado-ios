import XCTest

final class ErrorPresentationUITests: XCTestCase {
    @MainActor
    func testOfflineReaderShowsBookChapterAndActions() {
        let app = launchReader(autoChange: false)
        app.buttons["断网正文"].tap()
        XCTAssertTrue(app.staticTexts["正文加载失败"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "第一章 断网")).firstMatch.exists)
        XCTAssertTrue(app.buttons["error.changeSource"].exists)
        XCTAssertTrue(app.buttons["error.manageSources"].exists)
        app.buttons["error.back"].tap()
        XCTAssertTrue(app.buttons["断网正文"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFailedSourceRecoveryExplainsCandidateAndKeepsReturn() {
        let app = launchReader(autoChange: true)
        app.buttons["断网正文"].tap()
        XCTAssertTrue(app.staticTexts["自动换源失败"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "候选书源")).firstMatch.exists)
        app.buttons["error.back"].tap()
        XCTAssertTrue(app.buttons["断网正文"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFailedDirectoryRefreshHasChineseRetryAndDismiss() {
        let app = launchReader(autoChange: false)
        app.buttons["失败目录"].tap()
        XCTAssertTrue(app.staticTexts["刷新目录失败"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "断网书源")).firstMatch.exists)
        app.buttons["error.retry"].tap()
        XCTAssertTrue(app.staticTexts["刷新目录失败"].waitForExistence(timeout: 5))
        app.buttons["error.dismiss"].tap()
        XCTAssertFalse(app.staticTexts["刷新目录失败"].exists)
    }

    @MainActor
    private func launchReader(autoChange: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-reader-failure-gallery", "-autoChangeSource", autoChange ? "YES" : "NO",
            "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["断网正文"].waitForExistence(timeout: 10))
        return app
    }

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
