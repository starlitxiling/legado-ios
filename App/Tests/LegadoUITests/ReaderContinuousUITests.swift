import XCTest
import UIKit

final class ReaderContinuousUITests: XCTestCase {
    @MainActor
    func testStatusIconToggleDoesNotChangePanelAppearance() {
        let app = launch(mode: 0)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.otherElements.matching(identifier: "reader.body").firstMatch.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["界面"].tap(); app.buttons["信息"].tap()
        let toggle = app.switches["深色状态栏图标"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        let before = panelLuminance(app.screenshot().image)
        XCTAssertGreaterThan(before, 0.5)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["完成"].tap()
        app.buttons["界面"].tap(); app.buttons["信息"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let after = panelLuminance(app.screenshot().image)
        XCTAssertEqual(after, before, accuracy: 0.05)
    }

    private func panelLuminance(_ image: UIImage) -> Double {
        guard let source = image.cgImage,
              let sample = source.cropping(to: CGRect(x: 30, y: Double(source.height) * 0.8, width: 2, height: 2)) else {
            XCTFail("Screenshot pixels unavailable"); return -1
        }
        var pixels = [UInt8](repeating: 0, count: 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Double(Int(pixels[0]) + Int(pixels[1]) + Int(pixels[2])) / 765
    }

    @MainActor
    func testCurlTurnsBothDirectionsAndStopsAtChapterBoundary() {
        let app = launch(mode: 2)
        let body = app.otherElements.matching(identifier: "reader.body").firstMatch
        let original = body.value as? String
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.65))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.65)).press(forDuration: 0.05, thenDragTo: start, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertEqual(body.value as? String, original)
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.65)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "第 1 章，第 2 页"), object: body)], timeout: 5), .completed)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.65)).press(forDuration: 0.05, thenDragTo: start, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", original!), object: body)], timeout: 5), .completed)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.35)).tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "第 1 章，第 2 页"), object: body)], timeout: 5), .completed)
    }

    @MainActor
    func testContinuousScrollContainsWholeChapterAndCrossesToNext() {
        let app = launch(mode: 3)
        XCTAssertGreaterThan(app.otherElements.matching(identifier: "reader.body").count, 2)
        let scroll = app.scrollViews["reader.scroll"]
        XCTAssertTrue(scroll.exists)
        for _ in 0..<10 where !(scroll.value as? String ?? "").contains("第 2 章") { scroll.swipeUp() }
        XCTAssertTrue((scroll.value as? String ?? "").contains("第 2 章"))
        let before = scroll.value as? String
        scroll.swipeDown()
        XCTAssertNotEqual(scroll.value as? String, before)
        XCTAssertTrue(app.buttons["返回"].exists || app.otherElements.matching(identifier: "reader.body").firstMatch.exists)
    }

    @MainActor
    func testUnderlineOptionsPersistAfterClosingPanel() {
        let app = launch(mode: 0)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["界面"].tap()
        let entry = app.buttons["下划线"]
        if !entry.isHittable { app.scrollViews.firstMatch.swipeLeft() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        app.buttons["reader.underline.mode"].tap(); app.buttons["双虚线"].tap()
        XCTAssertTrue(app.switches["正文下划线"].exists)
        XCTAssertTrue(app.switches["标题下划线"].exists)
        app.sliders["线宽"].adjust(toNormalizedSliderPosition: 0.3)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["完成"].tap(); app.buttons["收起"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["界面"].tap()
        if !entry.isHittable { app.scrollViews.firstMatch.swipeLeft() }
        entry.tap()
        XCTAssertTrue(app.buttons["reader.underline.mode"].label.contains("双虚线"))
    }

    @MainActor
    func testTemplateEditorAndStatusIconSetting() {
        let app = launch(mode: 0)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["界面"].tap(); app.buttons["信息"].tap()
        XCTAssertTrue(app.switches["深色状态栏图标"].waitForExistence(timeout: 5))
        let toggle = app.switches["深色状态栏图标"]
        if toggle.value as? String == "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["reader.template.页脚左"].tap()
        let editor = app.textViews["reader.template.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.buttons["清空模板"].tap(); editor.tap()
        editor.typeText("Custom {页码}/{总页数}")
        app.buttons["保存模板"].tap()
        app.buttons["reader.template.页脚左"].tap()
        XCTAssertEqual(editor.value as? String, "Custom {页码}/{总页数}")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["完成"].tap(); app.buttons["收起"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Custom 1/")).firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    func testStyleNetworkImportValidationSharingAndReviewIcon() {
        let app = launch(mode: 0)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["界面"].tap(); app.buttons["reader.style.add"].tap()
        XCTAssertTrue(app.buttons["网络导入样式"].waitForExistence(timeout: 5))
        app.buttons["网络导入样式"].tap()
        app.alerts.textFields.firstMatch.tap(); app.alerts.textFields.firstMatch.typeText("invalid")
        app.alerts.buttons["导入"].tap()
        XCTAssertTrue(app.alerts["阅读样式"].waitForExistence(timeout: 5)); app.alerts.buttons["好"].tap()
        app.buttons["段评图标"].tap()
        let preset = app.buttons["圆角气泡"]
        for _ in 0..<6 where !preset.isHittable { app.swipeUp() }
        XCTAssertTrue(preset.isHittable); preset.tap()
        for _ in 0..<6 where !app.sliders["图标缩放 (%)"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.descendants(matching: .any)["reader.review.icon"].firstMatch.exists)
        app.sliders["图标缩放 (%)"].adjust(toNormalizedSliderPosition: 0.7)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["分享样式"].tap()
        XCTAssertTrue(app.buttons["reader.style.share"].waitForExistence(timeout: 5)); app.buttons["reader.style.share"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells["保存到“文件”"].exists)
    }

    @MainActor
    private func launch(mode: Int) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-detail-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO",
            "-doubleHorizontalPage", "0", "-pageAnim", String(mode), "-readStyleSelect", "0", "-textSize", "24", "-shareLayout", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 15))
        app.buttons["detail.read"].tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "reader.body").firstMatch.waitForExistence(timeout: 10))
        return app
    }
}
