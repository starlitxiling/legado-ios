import XCTest

final class ReaderBackgroundUITests: XCTestCase {
    @MainActor
    func testPrimaryColorControlsBuiltInBackgroundAndStylePreview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-detail-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO",
            "-doubleHorizontalPage", "0", "-readStyleSelect", "0", "-shareLayout", "NO", "-isNightTheme", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 15))
        app.buttons["detail.read"].tap()
        XCTAssertTrue(app.otherElements["reader.body"].waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["界面"].tap()
        XCTAssertTrue(app.buttons["背景图片"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "文字颜色")).firstMatch.exists)
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "背景颜色")).firstMatch.exists)
        app.buttons["背景图片"].tap()
        XCTAssertTrue(app.buttons["从相册选择"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["从文件选择"].exists)
        let background = app.buttons["reader.background.护眼漫绿.jpg"]
        for _ in 0..<5 where !background.isHittable { app.swipeUp() }
        XCTAssertTrue(background.isHittable); background.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let preview = app.buttons["reader.style.0"]
        for _ in 0..<5 where !preview.isHittable { app.swipeUp() }
        XCTAssertTrue(preview.exists)
        XCTAssertEqual(preview.value as? String, "护眼漫绿.jpg")
        app.buttons["完成"].tap()
        app.buttons["收起"].tap()
        XCTAssertTrue(app.images["reader.background.image"].firstMatch.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "b2-builtin-background"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 15))
        app.buttons["detail.read"].tap()
        XCTAssertTrue(app.images["reader.background.image"].firstMatch.waitForExistence(timeout: 10))
    }
}
