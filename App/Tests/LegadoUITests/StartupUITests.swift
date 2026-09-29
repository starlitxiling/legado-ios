import XCTest

final class StartupUITests: XCTestCase {
    @MainActor
    func testRSSImportErrorUsesChineseOperation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-showRss", "YES", "-autoTaskService", "NO", "-syncBookProgress", "NO", "-auto_refresh", "NO", "-defaultToRead", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        app.tabBars.buttons["订阅"].tap()
        app.buttons["rss.menu"].tap()
        app.buttons["导入 JSON 或链接"].tap()
        let text = app.textViews["rss.importText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap(); text.typeText("{")
        app.buttons["导入"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "导入订阅源失败")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["invalidSource"].exists)
    }

    @MainActor
    func testLabeledTabsAndSettingsRemainUsableAfterForegrounding() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-autoTaskService", "NO", "-syncBookProgress", "NO", "-auto_refresh", "NO", "-defaultToRead", "NO",
            "-showDiscovery", "YES", "-showRss", "YES", "-defaultHomePage", "bookshelf", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        for title in ["书架", "发现", "订阅", "我的"] { XCTAssertTrue(app.tabBars.buttons[title].exists) }
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["书源管理"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["MCP 服务"].exists)
        XCTAssertFalse(app.staticTexts["本轮暂不启用"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["书源管理"].waitForExistence(timeout: 5))
        app.staticTexts["书源管理"].tap()
        XCTAssertTrue(app.navigationBars["书源"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "c3-tabs-accessibility"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    func testColdLaunchReachesInteractiveBookshelf() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-autoTaskService", "NO", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20),
                      "App must leave the database loading screen and display the main tabs")
        XCTAssertFalse(app.staticTexts["正在打开书库"].exists)
        XCTAssertTrue(app.navigationBars["书架"].exists)
        openSettings(app)
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testThemePresetsAndEInkRemainInteractive() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-autoTaskService", "NO", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        openSettings(app)
        let themeSettings = app.staticTexts["主题设置"]
        if !themeSettings.isHittable { app.swipeUp() }
        XCTAssertTrue(themeSettings.waitForExistence(timeout: 5))
        themeSettings.tap()
        app.staticTexts["主题列表"].tap()
        for name in ["默认", "典雅蓝", "黑白", "A屏黑"] {
            let preset = app.buttons[name]
            XCTAssertTrue(preset.waitForExistence(timeout: 5))
            preset.tap()
            XCTAssertTrue(app.navigationBars["主题列表"].exists)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "theme-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.buttons["默认"].tap()
        app.navigationBars["主题列表"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["主题设置"].waitForExistence(timeout: 5))
        app.navigationBars["主题设置"].buttons.element(boundBy: 0).tap()
        for _ in 0..<4 where !app.segmentedControls["settings.themeMode"].isHittable { app.swipeDown() }
        app.segmentedControls["settings.themeMode"].buttons["墨水屏"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "theme-eink"; attachment.lifetime = .keepAlways; add(attachment)
        app.segmentedControls["settings.themeMode"].buttons["系统"].tap()
    }

    @MainActor
    func testFourIconTabsAndMovedSearchAndSources() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-showDiscovery", "YES", "-showRss", "YES", "-defaultHomePage", "bookshelf", "-auto_refresh", "NO", "-defaultToRead", "NO"]
        app.launchArguments += ["-autoTaskService", "NO", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        for name in ["发现", "订阅", "我的", "书架"] {
            app.tabBars.buttons[name].tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
        }
        app.buttons["bookshelf.search"].tap()
        XCTAssertTrue(app.navigationBars["搜索"].waitForExistence(timeout: 5))
        app.navigationBars["搜索"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["书架"].waitForExistence(timeout: 5))
        openSettings(app)
        let sources = app.staticTexts["书源管理"]
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        sources.tap()
        XCTAssertTrue(app.navigationBars["书源"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "u1-source-entry"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testHiddenTabsKeepMyPageAndBookshelfReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-autoTaskService", "NO", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        openSettings(app)
        let settings = app.staticTexts["其它设置"]
        for _ in 0..<4 where !settings.isHittable { app.swipeUp() }
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        let discovery = app.switches["显示发现"], rss = app.switches["显示订阅"]
        XCTAssertTrue(discovery.waitForExistence(timeout: 5))
        if discovery.value as? String == "1" { discovery.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        if rss.value as? String == "1" { rss.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertEqual(discovery.value as? String, "0")
        XCTAssertEqual(rss.value as? String, "0")
        XCTAssertEqual(app.tabBars.buttons.count, 2)
        app.tabBars.buttons["书架"].tap()
        XCTAssertTrue(app.navigationBars["书架"].waitForExistence(timeout: 5))
        openSettings(app)
        XCTAssertTrue(app.navigationBars["其它设置"].waitForExistence(timeout: 5))
        discovery.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.tabBars.buttons["发现"].waitForExistence(timeout: 5))
        rss.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.tabBars.buttons["订阅"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 4)

    }

    @MainActor
    func testLauncherIconsAreAvailable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-autoTaskService", "NO", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        openSettings(app)
        let themeSettings = app.staticTexts["主题设置"]
        if !themeSettings.isHittable { app.swipeUp() }
        XCTAssertTrue(themeSettings.waitForExistence(timeout: 5))
        themeSettings.tap()
        let icons = app.buttons["切换图标"].exists ? app.buttons["切换图标"] : app.staticTexts["切换图标"]
        XCTAssertTrue(icons.waitForExistence(timeout: 5))
        icons.tap()
        XCTAssertTrue(app.staticTexts["默认图标"].waitForExistence(timeout: 5))
        let alternates = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "图标 "))
        XCTAssertGreaterThan(alternates.count, 0, app.debugDescription)
        XCTAssertFalse(app.staticTexts["当前安装包未包含备用图标，暂不能切换。"].exists)
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        let settings = app.tabBars.buttons["我的"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
    }

}
