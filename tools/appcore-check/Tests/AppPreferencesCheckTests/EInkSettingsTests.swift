import XCTest
import LegadoCore
@testable import SettingsBackupCheck

final class EInkSettingsTests: XCTestCase {
    func testDefaultsParseAndClamp() {
        let defaults = EInkSettings(values: EInkSettings.defaults)
        XCTAssertEqual(defaults, EInkSettings())
        XCTAssertEqual(defaults.refreshInterval, 6)
        XCTAssertEqual(defaults.paper, .paper)
        XCTAssertEqual(defaults.strokeWidth, -2.5)
        let custom = EInkSettings(values: [
            EInkSettings.refreshIntervalKey: .int(99), EInkSettings.paperKey: .string("warm"),
            EInkSettings.textWeightKey: .int(7), EInkSettings.sharpTextKey: .boolean(true),
            EInkSettings.imageModeKey: .string("threshold"), EInkSettings.thresholdKey: .int(1)
        ])
        XCTAssertEqual(custom.refreshInterval, 50)
        XCTAssertEqual(custom.paper, .warm)
        XCTAssertEqual(custom.textWeight, 2)
        XCTAssertEqual(custom.strokeWidth, -5)
        XCTAssertTrue(custom.sharpText)
        XCTAssertEqual(custom.imageMode, .threshold)
        XCTAssertEqual(custom.threshold, 5)
        XCTAssertTrue(custom.hideStatusBar)
        XCTAssertFalse(EInkSettings(values: [EInkSettings.hideStatusBarKey: .boolean(false)]).hideStatusBar)
        let unknown = EInkSettings(values: [EInkSettings.paperKey: .string("pink"), EInkSettings.imageModeKey: .string("x")])
        XCTAssertEqual(unknown.paper, .paper)
        XCTAssertEqual(unknown.imageMode, .levels)
    }

    func testRefreshCounterFlashesEveryIntervalAndCanBeDisabled() {
        var counter = EInkRefreshCounter()
        let flashes = (1...12).map { _ in counter.turn(interval: 6) }
        XCTAssertEqual(flashes.enumerated().filter(\.element).map(\.offset), [5, 11])
        XCTAssertFalse(counter.turn(interval: 0))
        XCTAssertEqual(counter.turns, 0)
        XCTAssertTrue(counter.turn(interval: 1))
        _ = counter.turn(interval: 3)
        counter.reset()
        XCTAssertEqual(counter.turns, 0)
    }

    @MainActor
    func testPreferencesExposeEInkDefaults() throws {
        let suite = "EInkSettingsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(EInkSettings(values: preferences.snapshot), EInkSettings())
        preferences.set(EInkSettings.refreshIntervalKey, .int(0))
        XCTAssertEqual(EInkSettings(values: AppPreferences(defaults: defaults).snapshot).refreshInterval, 0)
    }
}
