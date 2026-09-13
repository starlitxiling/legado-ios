import XCTest
@testable import LegadoCore

final class BackupTests: XCTestCase {
    func testLargeStreamingDeflateConsumesBufferedOutput() throws {
        let data = try fixture("large-streaming.zip")
        XCTAssertEqual(Array(data[6..<8]), [0x08, 0x08])
        XCTAssertEqual(Array(data[18..<26]), Array(repeating: 0, count: 8))
        let archive = try BackupArchive(data: data)
        XCTAssertEqual(archive.entries.count, 23)
        XCTAssertEqual(archive.files.count, 22)
        XCTAssertEqual(archive.entries["synthetic-directory/"], Data())
        XCTAssertEqual(archive.files["bookshelf.json"], Data(("[\"" + String(repeating: "a", count: 160792 - 4) + "\"]").utf8))
        XCTAssertEqual(archive.files["bookSource.json"], Data(("[\"" + String(repeating: "b", count: 12349274 - 4) + "\"]").utf8))
        for index in 0..<20 {
            XCTAssertEqual(archive.files[String(format: "synthetic%02d.json", index)], Data("[]".utf8))
        }
    }

    static var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Conformance/fixtures/backup")
    }

    func fixture(_ name: String = "backup2024-01-02.zip") throws -> Data {
        try Data(contentsOf: Self.fixtures.appendingPathComponent(name))
    }

    func testArchiveStoredDeflateAndDataDescriptors() throws {
        let archive = try BackupArchive(data: fixture())
        XCTAssertEqual(archive.files.count, 9)
        XCTAssertTrue(String(decoding: archive.files["bookshelf.json"]!, as: UTF8.self).contains("合成书"))
        let stored = try BackupArchive(data: fixture("stored.zip"))
        XCTAssertEqual(stored.files["empty.txt"], Data())
        XCTAssertEqual(stored.files["中文.txt"], Data("stored".utf8))
    }

    func testArchiveRejectsTraversalTruncationCorruptionAndLimits() throws {
        XCTAssertThrowsError(try BackupArchive(data: fixture("traversal.zip")))
        XCTAssertThrowsError(try BackupArchive(data: fixture().dropLast(8)))
        XCTAssertThrowsError(try BackupArchive(data: fixture(), maximumExpandedSize: 10))
        var corrupt = try fixture("stored.zip")
        let range = corrupt.range(of: Data("stored".utf8))!
        corrupt[range.lowerBound] ^= 1
        XCTAssertThrowsError(try BackupArchive(data: corrupt))
    }

    func testImportAndRepeatPreserveLocalRowsAndMergeReading() async throws {
        let database = try AppDatabase.inMemory()
        let importer = BackupImporter(database: database, localDeviceID: "local", now: { 123 })
        var current = ReadRecordRow()
        current.deviceId = "local"; current.bookName = "合成书"; current.author = "作者"
        current.readTime = 50; current.lastRead = 200; current.lastChapterIndex = 8
        try await ReadProgressRepository(database: database).upsert(current)
        var unrelated = BookRow()
        unrelated.bookUrl = "unrelated"; unrelated.name = "保留"
        try await BookshelfRepository(database: database).upsert(unrelated)
        let report = try await importer.importArchive(fixture())
        XCTAssertEqual(Set(report.importedFiles), ["bookshelf.json", "bookGroup.json", "bookmark.json", "bookSource.json", "rssSources.json", "replaceRule.json", "readRecord.json", "config.xml"])
        XCTAssertEqual(report.skippedFiles.sorted(), ["unknown.txt"])
        XCTAssertTrue(report.failures.isEmpty)
        _ = try await importer.importArchive(fixture())
        let books = try await BookshelfRepository(database: database).all()
        XCTAssertEqual(books.count, 2)
        XCTAssertTrue(books.first { $0.name == "合成书" }!.readConfig!.contains("reverseToc"))
        let sources = try await BookSourceRepository(database: database).all()
        XCTAssertEqual(sources.count, 1)
        XCTAssertTrue(sources[0].ruleSearch!.contains("tag.li"))
        let records = try await ReadProgressRepository(database: database).all()
        XCTAssertEqual(records[0].readTime, 50)
        XCTAssertEqual(records[0].lastChapterIndex, 8)
        let marks = try await BookmarkRepository(database: database).all()
        XCTAssertEqual(marks.count, 1)
        let rules = try await ReplaceRuleRepository(database: database).all()
        XCTAssertEqual(rules.count, 1)
    }

    func testMalformedFileIsReportedAndNextFileStillImports() async throws {
        let database = try AppDatabase.inMemory()
        let report = try await BackupImporter(database: database, localDeviceID: "local", now: { 0 })
            .importArchive(fixture("malformed-json.zip"))
        XCTAssertNotNil(report.failures["bookshelf.json"])
        XCTAssertEqual(report.importedFiles, ["bookmark.json"])
    }

    func testReadingMergeRemoteDurationAndMissingChapterFallback() {
        var current = ReadRecordRow()
        current.deviceId = "remote"; current.bookName = "book"; current.readTime = 50
        current.lastRead = 100; current.lastChapterIndex = 5; current.coverUrl = "cover"
        var incoming = current
        incoming.readTime = 10; incoming.lastRead = 200; incoming.lastChapterIndex = -1; incoming.coverUrl = " "
        let result = BackupImporter.mergeReading(current: current, incoming: incoming, localDeviceID: "local")
        XCTAssertEqual(result.readTime, 10)
        XCTAssertEqual(result.lastChapterIndex, 5)
        XCTAssertEqual(result.coverUrl, "cover")
    }

    func testLegacyBookTypeAndPersistedCoverNormalization() {
        var row = BookRow()
        row.type = 1; row.origin = "loc_book"
        row.customCoverUrl = "/old/covers/0123456789abcdef0123456789abcdef.cover"
        let result = BackupImporter.normalizeBook(row)
        XCTAssertEqual(result.type, 288)
        XCTAssertEqual(result.persistedCoverUrl, row.customCoverUrl)
        XCTAssertNil(result.customCoverUrl)
    }
}
