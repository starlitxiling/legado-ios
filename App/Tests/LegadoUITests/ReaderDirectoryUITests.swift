import XCTest

final class ReaderDirectoryUITests: XCTestCase {
    @MainActor
    func testFullScreenDirectorySearchBookmarkAndChapterJump() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-detail-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO", "-doubleHorizontalPage", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 15))
        app.buttons["detail.read"].tap()
        XCTAssertTrue(app.otherElements["reader.body"].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["目录"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["书签"].waitForExistence(timeout: 5))
        snapshot(app, "u6-reader-toc")
        app.segmentedControls.buttons["书签"].tap()
        app.buttons["添加当前位置书签"].tap()
        XCTAssertTrue(app.staticTexts["第一章 启航"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["目录"].tap()
        app.buttons["目录菜单"].tap()
        app.buttons["反转目录"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("第二章")
        XCTAssertTrue(app.buttons["reader.toc.chapter:1"].waitForExistence(timeout: 5))
        app.buttons["reader.toc.chapter:1"].tap()
        XCTAssertTrue(app.otherElements["reader.body"].waitForExistence(timeout: 10))
        XCTAssertTrue((app.otherElements["reader.body"].value as? String)?.hasPrefix("第 2 章") == true)
    }

    @MainActor
    func testLocalEpubHierarchyAndPDFOutline() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-localbook-gallery", "-syncBookProgress", "NO", "-syncBookProgressPlus", "NO", "-doubleHorizontalPage", "0", "-clickImgWay", "3"]
        for format in ["epub", "pdf"] {
            app.launch()
            let status = app.staticTexts["localbook.status"]
            XCTAssertTrue(status.waitForExistence(timeout: 15))
            expectation(for: NSPredicate(format: "label == %@", "10 formats passed"), evaluatedWith: status)
            waitForExpectations(timeout: 60)
            app.buttons["localbook.open." + format].tap()
            XCTAssertTrue(app.otherElements["reader.body"].waitForExistence(timeout: 15))
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            app.buttons["目录"].tap()
            XCTAssertTrue(app.segmentedControls.buttons["目录"].waitForExistence(timeout: 5))
            if format == "pdf" {
                app.segmentedControls.buttons["大纲"].tap()
                XCTAssertTrue(app.buttons["reader.toc.node:1"].waitForExistence(timeout: 5))
                app.buttons["reader.toc.node:1"].tap()
                XCTAssertTrue(app.images["正文图片"].waitForExistence(timeout: 10))
                snapshot(app, "u6-reader-outline-page")
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                app.buttons["目录"].tap()
                app.segmentedControls.buttons["大纲"].tap()
            } else {
                let collapse = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "折叠或展开 Part")).firstMatch
                XCTAssertTrue(collapse.waitForExistence(timeout: 5))
                collapse.tap(); collapse.tap()
            }
            snapshot(app, "u6-reader-toc-" + format)
            app.terminate()
        }
    }

    @MainActor private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
