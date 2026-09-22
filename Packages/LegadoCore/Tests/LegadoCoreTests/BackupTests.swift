import XCTest
@testable import LegadoCore

final class BackupTests: XCTestCase {
    func testImportFailureFormatterReceivesFileAndOriginalError() async throws {
        let importer = BackupImporter(database: try .inMemory(), localDeviceID: "fixture", describeError: { error, file in
            file + ": " + String((error as NSError).code)
        })
        let report = try await importer.importArchive(fixture("malformed-json.zip"))
        XCTAssertEqual(report.failures["bookshelf.json"], "bookshelf.json: 3840")
        XCTAssertEqual(report.importedCounts["bookmark.json"], 1)
    }

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

extension BackupTests {
    func testBackupAESAndroidVectorAndInvalidCiphertext() throws {
        let aes = BackupAES()
        let plain = Data("[]".utf8)
        let cipher = Data("bF6sxj5FCEbxFyh1WJYCrQ==".utf8)
        XCTAssertEqual(try aes.encrypt(plain), cipher)
        XCTAssertEqual(try aes.decrypt(cipher), plain)
        XCTAssertNotEqual(try? BackupAES(password: "wrong").decrypt(cipher), plain)
        for value in ["", "not base64", "YQ=="] {
            XCTAssertThrowsError(try aes.decrypt(Data(value.utf8)))
        }
        for value in ["", String(repeating: "a", count: 16), "password-value"] {
            let bytes = Data(value.utf8)
            let custom = BackupAES(password: "test")
            XCTAssertEqual(try custom.decrypt(custom.encrypt(bytes)), bytes)
        }
    }

    func testHighlightArrayRestoresAndInvalidFilesPreserveRules() async throws {
        let database = try AppDatabase.inMemory()
        let importer = BackupImporter(database: database, localDeviceID: "test")
        let initial = try await importer.importArchive(BackupReviewTests.archive([
            "highlightRule.json": #"[{"pattern":"sample","timeoutMillisecond":0}]"#]))
        XCTAssertEqual(initial.importedCounts["highlightRule.json"], 1)
        let before = try await Repository<HighlightRule>(database: database).all()
        XCTAssertEqual(before.first?.timeoutMillisecond, 3000)
        for invalid in [#"{"a":[],"b":[],"c":"","d":true,"e":true,"f":true}"#, "{", "[null]"] {
            let report = try await importer.importArchive(BackupReviewTests.archive([
                "highlightRule.json": invalid, "servers.json": "bF6sxj5FCEbxFyh1WJYCrQ=="]))
            XCTAssertTrue(report.failures.isEmpty)
            XCTAssertTrue(report.skippedFiles.contains("highlightRule.json"))
            XCTAssertNotNil(report.skippedReasons["highlightRule.json"])
            XCTAssertEqual(report.importedCounts["servers.json"], 0)
            let after = try await Repository<HighlightRule>(database: database).all()
            XCTAssertEqual(after.map(\.uuid), before.map(\.uuid))
        }
        let empty = try await importer.importArchive(BackupReviewTests.archive(["highlightRule.json": "[]"]))
        XCTAssertEqual(empty.importedCounts["highlightRule.json"], 0)
        let after = try await Repository<HighlightRule>(database: database).all()
        XCTAssertTrue(after.isEmpty)
    }

    func testServersPlainEncryptedAndWrongPassword() async throws {
        let database = try AppDatabase.inMemory()
        let importer = BackupImporter(database: database, localDeviceID: "test")
        for value in ["[]", "bF6sxj5FCEbxFyh1WJYCrQ=="] {
            let report = try await importer.importArchive(BackupReviewTests.archive(["servers.json": value]))
            XCTAssertTrue(report.failures.isEmpty)
            XCTAssertEqual(report.importedCounts["servers.json"], 0)
        }
        let report = try await BackupImporter(database: database, localDeviceID: "test", password: "wrong")
            .importArchive(BackupReviewTests.archive(["servers.json": "bF6sxj5FCEbxFyh1WJYCrQ=="]))
        XCTAssertNotNil(report.failures["servers.json"])
        XCTAssertNil(report.importedCounts["servers.json"])
    }

    func testEncryptedSourceStateAndPreferencesRoundTrip() async throws {
        let database = try AppDatabase.inMemory()
        let aes = BackupAES(password: "test")
        let cookies = #"[{"url":"example.invalid","cookie":"session=synthetic"}]"#
        let caches = #"[{"key":"v_sample","value":"synthetic","deadline":0}]"#
        let files = ["cookies.json": String(decoding: try aes.encrypt(Data(cookies.utf8)), as: UTF8.self),
                     "runtimeSourceCache.json": String(decoding: try aes.encrypt(Data(caches.utf8)), as: UTF8.self)]
        let report = try await BackupImporter(database: database, localDeviceID: "test", password: "test")
            .importArchive(BackupReviewTests.archive(files))
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(report.importedCounts["cookies.json"], 1)
        XCTAssertEqual(report.importedCounts["runtimeSourceCache.json"], 1)
        let output = try await BackupExporter(database: database).export(
            preferences: ["localPassword": .string("test"), "webDavPassword": .string("synthetic-secret")], includeSourceState: true)
        let archive = try BackupArchive(data: output)
        for name in ["servers.json", "cookies.json", "runtimeSourceCache.json"] {
            let encrypted = try XCTUnwrap(archive.files[name])
            XCTAssertFalse(BackupAES.isJSONArray(encrypted))
            XCTAssertTrue(BackupAES.isJSONArray(try aes.decrypt(encrypted)))
        }
        let preferences = try AndroidPreferencesXML.decode(XCTUnwrap(archive.files["config.xml"]))
        XCTAssertNil(preferences["localPassword"])
        XCTAssertNotEqual(preferences["webDavPassword"], .string("synthetic-secret"))
        let restored = try AppDatabase.inMemory()
        let restoredReport = try await BackupImporter(database: restored, localDeviceID: "test",
            currentPreferences: ["localPassword": .string("test")]).importArchive(output)
        XCTAssertTrue(restoredReport.failures.isEmpty)
        XCTAssertEqual(restoredReport.preferences?["webDavPassword"], .string("synthetic-secret"))
        XCTAssertEqual(restoredReport.importedCounts["cookies.json"], 1)
        XCTAssertEqual(restoredReport.importedCounts["runtimeSourceCache.json"], 1)
    }

    func testSourceStatePasswordPreflightAndPlainCacheCompatibility() async throws {
        let database = try AppDatabase.inMemory()
        let payload = BackupReviewTests.archive(["cookies.json": "[]", "bookshelf.json": "[]"])
        for password in [nil, "", "   "] as [String?] {
            do {
                _ = try await BackupImporter(database: database, localDeviceID: "test", password: password).importArchive(payload)
                XCTFail("Cookie restore requires a nonblank password")
            } catch let error as BackupError {
                XCTAssertEqual(error, .passwordRequired(file: "cookies.json"))
            }
        }
        let invalid = try await BackupImporter(database: database, localDeviceID: "test", password: "test").importArchive(payload)
        XCTAssertNotNil(invalid.failures["cookies.json"])
        XCTAssertTrue(invalid.importedFiles.isEmpty)
        let cache = BackupReviewTests.archive(["runtimeSourceCache.json": "[]"])
        let report = try await BackupImporter(database: database, localDeviceID: "test", password: "test").importArchive(cache)
        XCTAssertEqual(report.importedCounts["runtimeSourceCache.json"], 0)
        do {
            _ = try await BackupImporter(database: database, localDeviceID: "test").importArchive(cache)
            XCTFail("Plain cache restore also requires a nonblank password")
        } catch let error as BackupError {
            XCTAssertEqual(error, .passwordRequired(file: "runtimeSourceCache.json"))
        }
        let ignored = try await BackupImporter(database: database, localDeviceID: "test").importArchive(payload,
            selection: BackupSelection(values: ["ignoreCookies": true]))
        XCTAssertTrue(ignored.failures.isEmpty)
        XCTAssertTrue(ignored.skippedFiles.contains("cookies.json"))
        do {
            _ = try await BackupExporter(database: database).export(includeSourceState: true)
            XCTFail("Source state export requires a nonblank password")
        } catch BackupError.passwordRequired(_) {}
        let cipher = String(decoding: try BackupAES(password: "test").encrypt(Data("[]".utf8)), as: UTF8.self)
        let wrong = try await BackupImporter(database: database, localDeviceID: "test", password: "wrong")
            .importArchive(BackupReviewTests.archive(["cookies.json": cipher, "bookshelf.json": "[]"]))
        XCTAssertNotNil(wrong.failures["cookies.json"])
        XCTAssertTrue(wrong.importedFiles.isEmpty)
    }

    func testWebDavPasswordFallbackPreservesExistingValue() async throws {
        let database = try AppDatabase.inMemory()
        let xml = String(decoding: AndroidPreferencesXML.encode(["webDavPassword": .string("legacy-plaintext")]), as: UTF8.self)
        let payload = BackupReviewTests.archive(["config.xml": xml])
        let retained = try await BackupImporter(database: database, localDeviceID: "test",
            currentPreferences: ["webDavPassword": .string("existing")]).importArchive(payload)
        XCTAssertNil(retained.preferences?["webDavPassword"])
        let restored = try await BackupImporter(database: database, localDeviceID: "test").importArchive(payload)
        XCTAssertEqual(restored.preferences?["webDavPassword"], .string("legacy-plaintext"))
    }
}
