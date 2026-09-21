import XCTest
import LegadoCore
@testable import ReaderCheck

final class ReaderInterfaceConfigTests: XCTestCase {
    @MainActor
    func testStringBackedNumericPreferencesLoadWithoutDiscardingStyles() async throws {
        let suite = "ReaderArguments." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("24", forKey: "textSize"); defaults.set("0.25", forKey: "letterSpacing")
        defaults.set("YES", forKey: "showHeaderLine"); defaults.set("invalid", forKey: "paddingTop")
        let settings = ReaderSettings.load(from: defaults)
        XCTAssertEqual(settings.textSize, 24)
        XCTAssertEqual(settings.letterSpacing, 0.25)
        XCTAssertTrue(settings.configuration.showHeaderLine)
        let store = ReaderStyleStore(database: try AppDatabase.inMemory(), defaults: defaults)
        try await store.load()
        XCTAssertEqual(store.styles.count, 6)
        XCTAssertEqual(store.current.textSize, 24)
        XCTAssertEqual(store.current.letterSpacing, 0.25)
    }

    func testAllClickActionsRoundTripAndMenuCannotBeLost() {
        let name = "ReaderClick.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        for raw in -1...13 {
            let action = ReaderTapAction(rawValue: raw)!
            var map = ReaderTouchMap.defaultActions
            map[0] = action
            ReaderTouchMap.save(map, to: defaults)
            XCTAssertEqual(ReaderTouchMap.load(from: defaults)[0], action)
            XCTAssertEqual(ReaderTouchMap.action(x: 5, y: 5, width: 300, height: 600, actions: map), action)
        }
        ReaderTouchMap.save(Array(repeating: .next, count: 9), to: defaults)
        XCTAssertEqual(ReaderTouchMap.load(from: defaults)[4], .menu)
        XCTAssertEqual(ReaderTouchMap.normalized([]), ReaderTouchMap.defaultActions)
    }

    func testCompleteReaderConfigurationSurvivesSettingsPersistence() {
        let name = "ReaderStyle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var configuration = ReadBookConfig()
        configuration.name = "Custom"; configuration.bgStr = "#123456"
        configuration.letterSpacing = 0.25; configuration.headerPaddingTop = 150
        configuration.footerPaddingLeft = 30; configuration.tipFooterMiddle = 10
        configuration.titleFont = "ExampleFont"; configuration.textBold = 1
        configuration.titleBold = 2; configuration.textSize = 6; configuration.tipHeaderLeftTemplate = "Custom header"
        var settings = ReaderSettings(configuration: configuration)
        settings.paddingBottom = 300; settings.lineSpacingExtra = 0
        settings.save(to: defaults)
        XCTAssertEqual(ReaderSettings.load(from: defaults), settings)
        settings.textSize = -1; settings.paddingTop = 900
        XCTAssertEqual(settings.normalized.textSize, 5)
        XCTAssertEqual(settings.normalized.paddingTop, 400)
    }

    @MainActor
    func testStylesPersistInBackupStorageAndSharedLayoutKeepsSelectedColors() async throws {
        let name = "ReaderStyles.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let database = try AppDatabase.inMemory()
        let store = ReaderStyleStore(database: database, defaults: defaults)
        try await store.load()
        XCTAssertEqual(store.current.textSize, 24)
        try await store.setSharedLayout(true)
        var current = store.current; current.textSize = 33
        try await store.update(current)
        try await store.select(2)
        XCTAssertEqual(store.current.textSize, 33)
        XCTAssertEqual(store.current.bgStr, "#DDC090")
        let restored = ReaderStyleStore(database: database, defaults: defaults)
        try await restored.load()
        XCTAssertEqual(restored.current, store.current)
        let saved = try await database.backupConfiguration(named: "readConfig.json")
        XCTAssertEqual(try ReadBookConfig.importThemes(XCTUnwrap(saved)).count, 6)
        try await restored.setSharedLayout(false)
        XCTAssertEqual(restored.current.textSize, 20)
        var imported = ReadBookConfig(); imported.name = "Imported"; imported.textSize = 40
        try await restored.importStyles(ReadBookConfig.exportThemes([imported]))
        XCTAssertEqual(restored.current.name, "Imported")
        try await restored.deleteSelected()
        XCTAssertEqual(restored.styles.count, 6)
    }

    func testBundledReaderStylesMatchKotlin() throws {
        let styles = try ReadBookConfig.bundledStyles()
        XCTAssertEqual(styles.count, 6)
        XCTAssertEqual(styles[0].textSize, 24)
        XCTAssertEqual(styles[0].paddingLeft, 22)
        XCTAssertEqual(styles[0].footerPaddingBottom, 10)
        XCTAssertEqual(styles[0].letterSpacing, 0)
        XCTAssertEqual(styles[0].tipHeaderLeft, 1)
        XCTAssertEqual(styles[0].tipFooterLeft, 7)
        XCTAssertEqual(styles.map { $0.bgStr.uppercased() }, ["#FFC0EDC6", "#FFFFFF", "#DDC090", "#C2D8AA", "#DBB8E2", "#ABCEE0"])
    }
}
