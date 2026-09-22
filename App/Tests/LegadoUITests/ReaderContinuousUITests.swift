import XCTest

final class ReaderContinuousUITests: XCTestCase {
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
