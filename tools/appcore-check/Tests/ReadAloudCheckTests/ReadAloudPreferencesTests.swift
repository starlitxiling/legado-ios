import XCTest
@testable import ReadAloudCheck

final class ReadAloudPreferencesTests: XCTestCase {
    func testSpeedMatchesKotlinSynthesizerScale() {
        XCTAssertEqual(ReadAloudPreferences.httpSpeed(0.5), 5)
        XCTAssertEqual(ReadAloudPreferences.httpSpeed(1), 10)
        XCTAssertEqual(ReadAloudPreferences.httpSpeed(3), 30)
    }
    func testPreferencesUseExplicitIsolatedStore() {
        let name = "ReadAloudTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.removePersistentDomain(forName: name)
        let model = ReadAloudPreferences(defaults: defaults)
        XCTAssertEqual(model.rate, 1); XCTAssertEqual(model.volume, 1); XCTAssertNil(model.sourceID)
        model.rate = 2; model.volume = 0.4; model.sourceID = 42
        let restored = ReadAloudPreferences(defaults: defaults)
        XCTAssertEqual(restored.rate, 2); XCTAssertEqual(restored.volume, 0.4); XCTAssertEqual(restored.sourceID, 42)
    }
}
