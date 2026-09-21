import XCTest

final class LocalBookUITests: XCTestCase {
    @MainActor
    func testTenFormatsAndIllustratedReaders() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-localbook-gallery"]
        app.launch()
        let status = app.staticTexts["localbook.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        let complete = NSPredicate(format: "label == %@", "10 formats passed")
        expectation(for: complete, evaluatedWith: status)
        waitForExpectations(timeout: 60)
        snapshot(app, name: "p7-ten-formats")
        for format in ["epub", "pdf", "azw3"] {
            app.buttons["localbook.open." + format].tap()
            let picture = app.images["正文图片"]
            for _ in 0..<4 {
                if picture.waitForExistence(timeout: 3) { break }
                app.swipeLeft()
            }
            XCTAssertTrue(picture.waitForExistence(timeout: 5), format)
            snapshot(app, name: "p7-reader-" + format)
            app.terminate()
            app.launch()
            XCTAssertTrue(status.waitForExistence(timeout: 15))
            expectation(for: complete, evaluatedWith: status)
            waitForExpectations(timeout: 60)
        }
    }

    @MainActor private func snapshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
