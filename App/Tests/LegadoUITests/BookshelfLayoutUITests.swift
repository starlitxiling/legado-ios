import XCTest

final class BookshelfLayoutUITests: XCTestCase {
    @MainActor
    func testAllSevenLayoutsAndRelaunchPersistence() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-bookshelf-gallery", "-reset-bookshelf-gallery"]
        app.launch()
        XCTAssertTrue(app.otherElements["bookshelf.contents"].waitForExistence(timeout: 15) || app.scrollViews["bookshelf.contents"].exists)
        snapshot(app, name: "u2-list")
        for title in ["紧凑列表", "网格 2 列", "网格 3 列", "网格 4 列", "网格 5 列", "网格 6 列", "列表"] {
            openLayout(app)
            let picker = app.buttons["bookshelf.layout"]
            for _ in 0..<5 where !picker.isHittable { app.swipeUp() }
            XCTAssertTrue(picker.isHittable)
            picker.tap()
            app.buttons[title].tap()
            app.buttons["确定"].tap()
            XCTAssertTrue(app.buttons["bookshelf.book.fixture:book:0"].waitForExistence(timeout: 5))
            if title == "网格 2 列" { snapshot(app, name: "u2-grid2") }
            if title == "网格 6 列" { snapshot(app, name: "u2-grid6") }
        }
        app.terminate()
        app.launchArguments = ["-bookshelf-gallery"]
        app.launch()
        openLayout(app)
        let picker = app.buttons["bookshelf.layout"]
        for _ in 0..<5 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.label.contains("列表") || (picker.value as? String)?.contains("列表") == true)
    }

    @MainActor
    func testFolderNavigationAndLongPressDetail() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-bookshelf-gallery", "-reset-bookshelf-gallery", "-bookshelf-gallery-dark"]
        app.launch()
        openLayout(app)
        app.buttons["bookshelf.groupStyle"].tap()
        app.buttons["文件夹"].tap()
        app.buttons["确定"].tap()
        let folder = app.buttons["bookshelf.folder.1"]
        for _ in 0..<6 {
            if folder.isHittable && folder.frame.maxY < app.frame.maxY - 40 { break }
            app.scrollViews["bookshelf.contents"].swipeUp()
        }
        XCTAssertTrue(folder.isHittable)
        snapshot(app, name: "u2-folders-dark")
        folder.tap()
        XCTAssertTrue(app.navigationBars["书架(Sample Group)"].waitForExistence(timeout: 5))
        let book = app.buttons["bookshelf.book.fixture:book:0"]
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        book.press(forDuration: 0.8)
        XCTAssertTrue(app.navigationBars["书籍详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample Book 01"].exists)
    }

    @MainActor private func openLayout(_ app: XCUIApplication) {
        let menu = app.buttons["bookshelf.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.tap()
        app.buttons["书架布局"].tap()
        XCTAssertTrue(app.navigationBars["书架布局"].waitForExistence(timeout: 5))
    }

    @MainActor private func snapshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
