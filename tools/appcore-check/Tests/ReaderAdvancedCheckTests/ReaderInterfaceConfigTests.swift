import XCTest
import LegadoCore
import GRDB
import CoreGraphics
@testable import ReaderCheck

final class ReaderInterfaceConfigTests: XCTestCase {
    func testPaperBackUsesSolidOrAverageImageColor() throws {
        var settings = ReaderSettings()
        settings.configuration.bgType = 0; settings.configuration.bgStr = "#FF123456"
        XCTAssertEqual(ReaderPaperColor.resolve(settings: settings), ARGBColor(0xFF123456))
        settings.configuration.bgType = 2; settings.configuration.bgAlpha = 100
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColorSpace(CGColorSpace(name: CGColorSpace.sRGB)!)
        context.setFillColor([1, 0, 0, 1])
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(ReaderPaperColor.resolve(settings: settings, image: image), ARGBColor(0xFFFF0000))
        settings.configuration.bgAlpha = 0; settings.configuration.bgTypeNight = 2; settings.theme = .night
        XCTAssertEqual(ReaderPaperColor.resolve(settings: settings, image: image), ARGBColor(0xFF000000))
    }

    @MainActor
    func testUnderlineEditsAndExportSetAndroidVersion() async throws {
        let suite = "R1.F6." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReaderStyleStore(database: try AppDatabase.inMemory(), defaults: defaults)
        try await store.load()
        XCTAssertEqual(try ReaderStyleArchive.decode(store.exportSelected()).configuration.underlineConfigVersion, 1)
        var config = store.current
        config.underlineMode = config.underlineMode == 1 ? 2 : 1
        try await store.update(config)
        XCTAssertEqual(store.current.underlineConfigVersion, 1)
        XCTAssertEqual(try ReaderStyleArchive.decode(store.exportSelected()).configuration.underlineMode, config.underlineMode)
    }

    @MainActor
    func testFallbackPreservesOriginalBytesBeforeSelectionAndEditing() async throws {
        for raw in [Data("{".utf8), Data(#"[{"textSize":22},{"textSize":"bad"}]"#.utf8)] {
            let database = try AppDatabase.inMemory()
            let suite = "R1.F1." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(37, forKey: "textSize")
            let shared = Data("broken shared".utf8)
            try await database.write { db in
                try db.execute(sql: "INSERT INTO backup_files(name, data) VALUES (?, ?), (?, ?)", arguments: ["readConfig.json", raw, "shareReadConfig.json", shared])
            }
            let store = ReaderStyleStore(database: database, defaults: defaults)
            try await store.load()
            XCTAssertEqual(defaults.integer(forKey: "textSize"), 37)
            try await store.select(0)
            var edited = store.current; edited.textSize = 26
            try await store.update(edited)
            let backups = try await database.write { db in
                try Row.fetchAll(db, sql: "SELECT name, data FROM backup_files WHERE name LIKE '%.broken-%'")
                    .map { ($0["name"] as String, $0["data"] as Data) }
            }
            XCTAssertTrue(backups.contains { $0.0.hasPrefix("readConfig.broken-") && $0.1 == raw })
            XCTAssertTrue(backups.contains { $0.0.hasPrefix("shareReadConfig.broken-") && $0.1 == shared })
            try await store.importStyles(Data(#"[{"textSize":19},{"textSize":"bad"}]"#.utf8))
            let count = try await database.write { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM backup_files WHERE name LIKE 'readConfig.broken-%'") }
            XCTAssertEqual(count, 2)
        }
    }

    func testStatusIconChoiceUsesDayNightAndEInkSettings() {
        var settings = ReaderSettings()
        settings.configuration.darkStatusIcon = false
        settings.configuration.darkStatusIconNight = true
        settings.configuration.darkStatusIconEInk = false
        XCTAssertFalse(settings.darkStatusIcons)
        settings.theme = .night
        XCTAssertTrue(settings.darkStatusIcons)
        settings.isEInk = true
        XCTAssertFalse(settings.darkStatusIcons)
    }

    @MainActor
    func testAllSixTemplatesSurviveStylePersistence() async throws {
        let database = try AppDatabase.inMemory()
        let suite = "ReaderTemplates." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReaderStyleStore(database: database, defaults: defaults)
        try await store.load()
        var config = store.current
        let paths: [WritableKeyPath<ReadBookConfig, String?>] = [\.tipHeaderLeftTemplate, \.tipHeaderMiddleTemplate,
            \.tipHeaderRightTemplate, \.tipFooterLeftTemplate, \.tipFooterMiddleTemplate, \.tipFooterRightTemplate]
        for (index, path) in paths.enumerated() { config[keyPath: path] = "Slot \(index): {页码}/{总页数}" }
        try await store.update(config)
        let restored = ReaderStyleStore(database: database, defaults: defaults)
        try await restored.load()
        for (index, path) in paths.enumerated() {
            XCTAssertEqual(ReaderInfo.parts(code: 0, template: restored.current[keyPath: path],
                values: ReaderInfoValues(page: "3", totalPages: "9")), [.text("Slot \(index): 3/9")])
        }
    }

    @MainActor
    func testDamagedSavedStylesFallBackWithoutBlockingReading() async throws {
        let suite = "ReaderStyleFallback." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "shareLayout")
        for damaged in ["{", "[]", #"[{"textSize":"bad"}]"#] {
            let database = try AppDatabase.inMemory()
            try await database.write { db in
                for name in ["readConfig.json", "shareReadConfig.json"] {
                    try db.execute(sql: "INSERT INTO backup_files(name, data) VALUES (?, ?)", arguments: [name, Data(damaged.utf8)])
                }
            }
            let log = AppLogStore()
            let store = ReaderStyleStore(database: database, defaults: defaults, log: log)
            try await store.load()
            XCTAssertEqual(store.styles.count, 6)
            XCTAssertEqual(store.current.textSize, try ReadBookConfig.bundledStyles()[5].textSize)
            XCTAssertTrue(log.snapshot().contains { $0.message.contains("readConfig.json") })
            XCTAssertTrue(log.snapshot().contains { $0.message.contains("shareReadConfig.json") })
            let original = try await database.backupConfiguration(named: "readConfig.json")
            XCTAssertEqual(original, Data(damaged.utf8))
        }
    }

    @MainActor
    func testStyleArchiveImportsWithoutOverwritingExistingBackground() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "StyleArchive." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: root.appendingPathComponent("day.png"))
        var config = ReadBookConfig(); config.bgType = 2; config.bgStr = "day.png"
        let packed = try ReaderStyleArchive.encode(config, background: { _ in Data("imported".utf8) })
        let store = ReaderStyleStore(database: try AppDatabase.inMemory(), defaults: defaults,
            resourceDirectory: root, fontDirectory: root.appendingPathComponent("fonts"))
        try await store.load()
        try await store.importStyles(packed)
        XCTAssertFalse(store.current.bgStr.hasPrefix("/"))
        XCTAssertNotEqual(store.current.bgStr, "day.png")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("day.png")), Data("existing".utf8))
        let exported = try ReaderStyleArchive.decode(store.exportSelected())
        XCTAssertEqual(exported.files[store.current.bgStr], Data("imported".utf8))
    }

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
