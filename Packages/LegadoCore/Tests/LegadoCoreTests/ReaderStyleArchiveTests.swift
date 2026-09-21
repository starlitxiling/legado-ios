import XCTest
@testable import LegadoCore

final class ReaderStyleArchiveTests: XCTestCase {
    func testPortableArchivePreservesBackgroundsAndFonts() throws {
        var config = ReadBookConfig()
        config.bgType = 2; config.bgStr = "day.png"
        config.bgTypeNight = 2; config.bgStrNight = "night.png"
        config.textFont = "TestFont"
        let packed = try ReaderStyleArchive.encode(config, background: { Data($0.utf8) }, font: { _ in ("font.ttf", Data([1, 2, 3])) })
        let files = try BackupArchive(data: packed).files
        let object = try JSONSerialization.jsonObject(with: XCTUnwrap(files["readConfig.json"]))
        XCTAssertNotNil(object as? [String: Any])
        let decoded = try ReaderStyleArchive.decode(packed)
        XCTAssertEqual(decoded.configuration.bgStr, "day.png")
        XCTAssertEqual(decoded.files["night.png"], Data("night.png".utf8))
        XCTAssertEqual(decoded.configuration.textFont, "font.ttf")
        XCTAssertEqual(decoded.files["font.ttf"], Data([1, 2, 3]))
    }

    func testMissingBackgroundDoesNotProduceBrokenExport() throws {
        var config = ReadBookConfig(); config.bgType = 2; config.bgStr = "missing.png"
        XCTAssertThrowsError(try ReaderStyleArchive.encode(config, background: { _ in nil }))
    }

    func testImportRejectsMissingAssetAndKeepsJSONCompatibility() throws {
        var config = ReadBookConfig(); config.bgType = 2; config.bgStr = "missing.png"
        let data = try BackupExporter.zip([("readConfig.json", JSONEncoder().encode(config))])
        XCTAssertThrowsError(try ReaderStyleArchive.decode(data))
        XCTAssertEqual(try ReadBookConfig.importThemes(ReadBookConfig.exportThemes([config])), [config])
    }
}
