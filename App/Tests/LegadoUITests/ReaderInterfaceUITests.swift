import XCTest

final class ReaderInterfaceUITests: XCTestCase {
    @MainActor
    func testStylesMarginsAndTitleInformation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-detail-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO", "-readStyleSelect", "0", "-textSize", "24", "-lineSpacingExtra", "10", "-letterSpacing", "0", "-shareLayout", "NO", "-doubleHorizontalPage", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 15))
        app.buttons["detail.read"].tap()
        let body = app.otherElements["reader.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["界面"].waitForExistence(timeout: 5))
        app.buttons["界面"].tap()
        XCTAssertTrue(app.sliders["字号"].waitForExistence(timeout: 5))
        snapshot(app, "u6-reader-interface")
        app.sliders["字号"].adjust(toNormalizedSliderPosition: 0.42)
        app.buttons.matching(identifier: "reader.style.2").firstMatch.tap()
        app.buttons["边距"].tap()
        XCTAssertTrue(app.switches["左右边距联动"].waitForExistence(timeout: 5))
        app.sliders.matching(identifier: "左").element(boundBy: 0).adjust(toNormalizedSliderPosition: 0.3)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["信息"].tap()
        XCTAssertTrue(app.navigationBars["信息与标题"].waitForExistence(timeout: 5))
        snapshot(app, "u6-reader-information")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["界面"].waitForExistence(timeout: 5))
        app.buttons["收起"].tap()
        snapshot(app, "u6-reader-typography")
    }

    @MainActor
    func testConfiguredDoublePageAndTapBookmark() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-detail-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO", "-readStyleSelect", "0", "-textSize", "24", "-lineSpacingExtra", "10", "-letterSpacing", "0", "-shareLayout", "NO", "-doubleHorizontalPage", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 15))
        app.buttons["detail.read"].tap()
        XCTAssertTrue(app.otherElements["reader.body"].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["doubleHorizontalPage"].waitForExistence(timeout: 5))
        app.buttons["doubleHorizontalPage"].tap()
        app.buttons["双页"].tap()
        app.buttons["完成"].tap()
        snapshot(app, "u6-reader-menu")
        app.buttons["收起"].tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "reader.body").element(boundBy: 1).waitForExistence(timeout: 5))
        snapshot(app, "u6-reader-double-page")
        app.swipeLeft()
        let page = app.otherElements.matching(identifier: "reader.body").element(boundBy: 0)
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertEqual(page.value as? String, "第 1 章，第 3 页")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["设置"].tap()
        let zones = app.buttons["点击区域设置"]
        for _ in 0..<10 where !zones.isHittable { app.swipeUp() }
        XCTAssertTrue(zones.isHittable); zones.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "左上：")).firstMatch.tap()
        app.buttons["添加书签"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["完成"].tap()
        app.buttons["收起"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["更多"].tap()
        app.buttons["书签列表"].tap()
        XCTAssertTrue(app.navigationBars["书签"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["第一章 启航"].exists)
    }

    @MainActor
    func testManualReplacementAndSimulatedReadingMenus() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-detail-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO", "-doubleHorizontalPage", "0", "-manualReplaceRule", "NO", "-readerMenuConfig", #"{"primary":["effectiveReplaces","simulatedReading"],"more":["bookmark","highlightRule","editContent","pageAnim","getProgress","coverProgress","reverseContent","replace","sameTitleRemoved","reSegment","delRubyTag","delHTag","imageStyle","reimportSource","updateToc","log","help"]}"#]
        app.launch()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 15))
        app.buttons["detail.read"].tap()
        XCTAssertTrue(app.otherElements["reader.body"].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["更多"].tap()
        let manual = app.buttons["手动替换"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap()
        XCTAssertTrue(app.switches["手动替换"].waitForExistence(timeout: 5))
        snapshot(app, "u6-reader-manual-replace")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 5)); app.buttons["更多"].tap()
        let simulated = app.buttons["模拟追读"]
        XCTAssertTrue(simulated.waitForExistence(timeout: 5)); simulated.tap()
        XCTAssertTrue(app.switches["模拟追读"].waitForExistence(timeout: 5))
        snapshot(app, "u6-reader-simulated")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["收起"].waitForExistence(timeout: 5)); app.buttons["收起"].tap()
        XCTAssertTrue(app.otherElements["reader.body"].exists)
    }

    @MainActor
    func testHighlightRuleEditorAndRenderedReader() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-detail-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO", "-doubleHorizontalPage", "0", "-manualReplaceRule", "NO", "-readerMenuConfig", #"{"primary":["highlightRule"],"more":["effectiveReplaces","simulatedReading","bookmark","editContent","pageAnim","getProgress","coverProgress","reverseContent","replace","sameTitleRemoved","reSegment","delRubyTag","delHTag","imageStyle","reimportSource","updateToc","log","help"]}"#]
        app.launch()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 15)); app.buttons["detail.read"].tap()
        XCTAssertTrue(app.otherElements["reader.body"].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["更多"].tap(); app.buttons["高亮规则"].tap()
        XCTAssertTrue(app.buttons["新建"].waitForExistence(timeout: 5)); app.buttons["新建"].tap()
        let name = app.textFields["名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Reader Highlight")
        let pattern = app.textViews["匹配文本"]; pattern.tap(); pattern.typeText("启航")
        app.switches["应用于标题"].tap()
        let bold = app.switches["粗体"]
        for _ in 0..<6 where !bold.isHittable { app.swipeUp() }
        XCTAssertTrue(bold.isHittable); bold.tap()
        snapshot(app, "u6-reader-highlight-editor")
        let advanced = app.buttons["高级样式 JSON"]
        for _ in 0..<6 where !advanced.isHittable { app.swipeUp() }
        XCTAssertTrue(advanced.isHittable); advanced.tap()
        let json = app.textViews["highlight.styleJSON"]
        XCTAssertTrue(json.waitForExistence(timeout: 5)); json.tap()
        let existing = json.value as? String ?? ""
        json.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        json.typeText(#"{"fill":-256,"textColor":-65536,"bold":true,"underline":{"kind":"WAVY"}}"#)
        app.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 5)); app.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["高亮规则"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Reader Highlight, 启航"].exists || app.staticTexts["Reader Highlight"].exists)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["收起"].waitForExistence(timeout: 5)); app.buttons["收起"].tap()
        XCTAssertTrue(app.otherElements["reader.body"].exists)
        snapshot(app, "u6-reader-highlight-rendered")
    }

    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
