import XCTest
import LegadoCore
@testable import SettingsBackupCheck

final class CoverSettingsTests: XCTestCase {
    func testLargeAndSmallSizesSelectByTextOverflow() {
        XCTAssertEqual(CoverTypography.columns("一二三四五六七", capacity: 3), ["一二三", "四五六", "七"])
        XCTAssertEqual(CoverTypography.columns("", capacity: 0), [])
        XCTAssertEqual(CoverTypography.size(width: 140, divisor: 7, large: 150, small: 75, custom: true, fits: { $0 <= 25 }), 15)
        XCTAssertEqual(CoverTypography.size(width: 70, divisor: 7, large: 150, small: 75, custom: true, fits: { $0 <= 25 }), 15)
        XCTAssertEqual(CoverTypography.size(width: 140, divisor: 7, large: 100, small: 100, custom: false, fits: { _ in false }), 140.0 / 9)
    }
    @MainActor func testRuleSaveRoundTripAndInvalidRuleDoesNotOverwrite() async throws {
        let database = try AppDatabase.inMemory()
        let model = CoverRuleSettingsModel(database: database)
        model.text = "{\"enable\":true,\"searchUrl\":\"https://example.test?q={{key}}\",\"coverRule\":\"img@src\",\"custom\":7}"
        await model.save()
        let saved = try await database.backupConfiguration(named: "coverRule.json")
        XCTAssertNotNil(saved)
        model.text = "{}"
        await model.save()
        let retained = try await database.backupConfiguration(named: "coverRule.json")
        XCTAssertEqual(retained, saved)
        await model.load()
        XCTAssertTrue(model.text.contains("custom"))
    }
}
