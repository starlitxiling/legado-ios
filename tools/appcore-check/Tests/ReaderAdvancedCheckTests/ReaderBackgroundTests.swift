import XCTest
import LegadoCore
@testable import ReaderCheck

final class ReaderBackgroundTests: XCTestCase {
    func testAllBackgroundTypesResolveAndRejectEscapingSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = ReaderSettings()
        XCTAssertNil(try settings.backgroundImageURL(directory: root))
        settings.configuration.bgType = 1
        settings.configuration.bgStr = "护眼漫绿.jpg"
        let bundled = try XCTUnwrap(settings.backgroundImageURL(directory: root))
        XCTAssertTrue(try Data(contentsOf: bundled).starts(with: [255, 216]))
        settings.configuration.bgType = 2
        settings.configuration.bgStr = "custom.jpg"
        XCTAssertEqual(try settings.backgroundImageURL(directory: root), root.appendingPathComponent("custom.jpg"))
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".jpg")
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.jpg"), withDestinationURL: outside)
        settings.configuration.bgStr = "escape.jpg"
        XCTAssertThrowsError(try settings.backgroundImageURL(directory: root))
        settings.configuration.bgType = 1
        settings.configuration.bgStr = "missing.jpg"
        XCTAssertThrowsError(try settings.backgroundImageURL(directory: root))
    }

    @MainActor
    func testBuiltInBackgroundPersistsAndSurvivesStyleArchiveAndLayoutReset() async throws {
        let suite = "BackgroundTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let database = try AppDatabase.inMemory()
        let store = ReaderStyleStore(database: database, defaults: defaults)
        try await store.load()
        var style = store.current
        style.bgType = 1; style.bgStr = "护眼漫绿.jpg"; style.bgAlpha = 65; style.textSize = 40
        try await store.update(style)
        try await store.restorePresetLayout()
        XCTAssertEqual(store.current.textSize, try ReadBookConfig.bundledStyles()[0].textSize)
        XCTAssertEqual(store.current.bgStr, "护眼漫绿.jpg")
        XCTAssertEqual(store.current.bgAlpha, 65)
        let archive = try store.exportSelected()
        let decoded = try ReaderStyleArchive.decode(archive)
        XCTAssertEqual(decoded.configuration.bgType, 1)
        XCTAssertEqual(decoded.configuration.bgStr, "护眼漫绿.jpg")
        XCTAssertEqual(Set(decoded.files.keys), ["readConfig.json"])
        let restored = ReaderStyleStore(database: database, defaults: defaults)
        try await restored.load()
        XCTAssertEqual(restored.current, store.current)
        try await restored.importStyles(archive)
        XCTAssertEqual(restored.current.bgType, 1)
        XCTAssertEqual(restored.current.bgStr, "护眼漫绿.jpg")
        let count = restored.styles.count
        try await restored.createStyle()
        XCTAssertEqual(restored.styles.count, count + 1)
        XCTAssertEqual(restored.selected, count)
        XCTAssertEqual(restored.current.name, "新样式")
    }

    func testNegativeLineSpacingSurvivesAndRangeMatchesAndroid() {
        var settings = ReaderSettings()
        settings.lineSpacingExtra = -10
        XCTAssertEqual(settings.normalized.lineSpacingExtra, -10)
        settings.lineSpacingExtra = 100
        XCTAssertEqual(settings.normalized.lineSpacingExtra, 40)
    }
}
