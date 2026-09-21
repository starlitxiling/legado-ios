import XCTest
@testable import ReaderCheck

final class ReaderBehaviorTests: XCTestCase {
    func testDefaultControlsAndPortablePreferenceRoundTrip() throws {
        XCTAssertEqual(ReaderBehaviorConfiguration.definitions.count, 41)
        let suite = "ReaderBehaviorTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("YES", forKey: "pullToToggleBookmark")
        defaults.set("150", forKey: "mouseWheelScrollSpeed")
        let arguments = ReaderBehaviorConfiguration(defaults: defaults)
        XCTAssertTrue(arguments.boolean("pullToToggleBookmark"))
        XCTAssertEqual(arguments.integer("mouseWheelScrollSpeed"), 150)
        defaults.removeObject(forKey: "pullToToggleBookmark")
        defaults.removeObject(forKey: "mouseWheelScrollSpeed")
        var value = ReaderBehaviorConfiguration(defaults: defaults)
        XCTAssertTrue(value.boolean("textFullJustify"))
        XCTAssertTrue(value.boolean("showBrightnessView"))
        XCTAssertFalse(value.boolean("pullToToggleBookmark"))
        value.set("doubleHorizontalPage", .string("3"))
        value.set("mouseWheelScrollSpeed", .int(900))
        value.set("screenOrientation", .string("invalid"))
        value.save(to: defaults)
        let loaded = ReaderBehaviorConfiguration(defaults: defaults)
        XCTAssertTrue(loaded.doublePage(width: 800, height: 1200, tablet: true))
        XCTAssertFalse(loaded.doublePage(width: 400, height: 800, tablet: false))
        XCTAssertEqual(loaded.integer("mouseWheelScrollSpeed"), 400)
        XCTAssertEqual(loaded.string("screenOrientation"), "0")
    }

    func testMenuPartitionRetainsNewActionsAndKeyboardCodes() {
        let reader = ReaderMenuPartition(primary: ["bookmark", "bookmark", "unknown"], more: ["editContent", "bookmark"]).normalized(selection: false)
        XCTAssertEqual(reader.primary.first, "bookmark")
        XCTAssertEqual(reader.more, ["editContent"])
        XCTAssertEqual(Set(reader.primary + reader.more), Set(ReaderMenuPartition.readerActions.map(\.0)))
        let selection = ReaderMenuPartition(primary: ["copy"], more: []).normalized(selection: true)
        XCTAssertEqual(selection.primary, ["copy"])
        XCTAssertTrue(selection.more.contains("highlight"))
        XCTAssertEqual(ReaderKeyboard.androidCode(character: "A"), 29)
        XCTAssertEqual(ReaderKeyboard.forward(code: 21, previous: "", next: ""), false)
        XCTAssertEqual(ReaderKeyboard.forward(code: 29, previous: "", next: "29,30"), true)
        XCTAssertNil(ReaderKeyboard.forward(code: 22, previous: "21", next: "29"))
    }

    func testInputThresholdsSeparateSwipeTapAndBookmark() {
        var value = ReaderBehaviorConfiguration(values: [:])
        XCTAssertEqual(value.gesture(x: -60, y: 8, duration: 0.2), .next)
        XCTAssertEqual(value.gesture(x: 2, y: 2, duration: 0.2), .tap)
        XCTAssertEqual(value.gesture(x: 2, y: 2, duration: 1), .none)
        XCTAssertEqual(value.gesture(x: 0, y: 100, duration: 0.2), .none)
        value.set("pullToToggleBookmark", .boolean(true))
        value.set("pullBookmarkDistance", .int(120))
        XCTAssertEqual(value.gesture(x: 0, y: 100, duration: 0.2), .none)
        XCTAssertEqual(value.gesture(x: 0, y: 125, duration: 0.2), .bookmark)
    }
}
