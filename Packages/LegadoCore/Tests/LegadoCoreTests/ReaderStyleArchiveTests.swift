import XCTest
@testable import LegadoCore

final class ReaderStyleArchiveTests: XCTestCase {
    func testMaxBackupStylesAcceptStringColorsAndUnknownFields() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let styles = try ReadBookConfig.importThemes(Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/reader/legado-max-styles.json")))
        XCTAssertEqual(styles.count, 6)
        XCTAssertEqual(styles.map { $0.underlineColor }, Array(repeating: -10239107, count: 6))
        XCTAssertEqual(styles[0].underlineWidth, 1)
        let source = try JSONDecoder().decode(BookSource.self, from: Data(#"{"bookSourceUrl":"https://example.test","bookSourceName":"Test","nextPageLazyLoad":true}"#.utf8))
        XCTAssertEqual(source.bookSourceName, "Test")
    }

    func testAndroidColorFormatsAndInvalidColorDefaults() throws {
        let config = try JSONDecoder().decode(ReadBookConfig.self, from: Data(##"{"underlineColor":"#FF63C37D","titleColor":"#123456","titleNumberColor":"4294967295","tipColor":"-16777216","tipDividerColor":"invalid","reviewIconColor":42}"##.utf8))
        XCTAssertEqual(config.underlineColor, -10239107)
        XCTAssertEqual(config.titleColor, -15584170)
        XCTAssertEqual(config.titleNumberColor, -1)
        XCTAssertEqual(config.tipColor, -16777216)
        XCTAssertEqual(config.tipDividerColor, -1)
        XCTAssertEqual(config.reviewIconColor, 42)
        for value in ["true", "[]", "{}", "null", "\"#123\"", "\"4294967296\"", "\"#GGGGGG\""] {
            let invalid = try JSONDecoder().decode(ReadBookConfig.self, from: Data("{\"underlineColor\":\(value)}".utf8))
            XCTAssertEqual(invalid.underlineColor, 0, value)
        }
    }

    func testPartlyDamagedArrayKeepsValidStylesAndSlotDefaults() throws {
        let styles = try ReadBookConfig.importThemes(Data(#"[{"name":"First"},{"textSize":"bad"},{"name":"Last"}]"#.utf8))
        XCTAssertEqual(styles.count, 3)
        XCTAssertEqual(styles[0].name, "First")
        XCTAssertEqual(styles[1], try ReadBookConfig.bundledStyles()[1])
        XCTAssertEqual(styles[2].name, "Last")
        XCTAssertThrowsError(try ReadBookConfig.importThemes(Data(#"[{"textSize":"bad"},{"paddingLeft":false}]"#.utf8))) { error in
            XCTAssertTrue(error.localizedDescription.contains("[0].textSize"), error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("[1].paddingLeft"), error.localizedDescription)
        }
    }

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
