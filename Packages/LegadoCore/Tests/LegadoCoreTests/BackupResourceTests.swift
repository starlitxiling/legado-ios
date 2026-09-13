import XCTest
@testable import LegadoCore

final class BackupResourceTests: XCTestCase {
    func testIgnoreCoverConfigPreservesFixedDefaultCovers() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/default-cover-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        let names = ["defaultCover.image", "defaultCoverDark.image", "other.png"]
        for directory in [source, target] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("covers"), withIntermediateDirectories: true)
            for name in names {
                try Data((directory == source ? "backup" : "local").utf8).write(to: directory.appendingPathComponent("covers/" + name))
            }
        }
        let data = try await BackupExporter(database: AppDatabase.inMemory(), resourceDirectory: source).export()
        let importer = BackupImporter(database: try AppDatabase.inMemory(), localDeviceID: "test", resourceDirectory: target)
        let report = try await importer.importArchive(data, selection: .init(values: ["coverConfig": true]))
        for name in names.prefix(2) {
            XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("covers/" + name)), Data("local".utf8))
            XCTAssertTrue(report.skippedFiles.contains("covers/" + name))
        }
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("covers/other.png")), Data("backup".utf8))
        _ = try await importer.importArchive(data)
        for name in names.prefix(2) {
            XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("covers/" + name)), Data("backup".utf8))
        }
    }

    func testResourcePathsRejectTraversalAndClassifyCovers() {
        XCTAssertNil(BackupResources.relativePath("/old/covers/../../secret"))
        XCTAssertNil(BackupResources.relativePath("https://example.invalid/covers/image"))
        XCTAssertEqual(BackupResources.relativePath("/old/covers/custom.png"), "covers/custom.png")
        XCTAssertTrue(BackupResources.persisted("covers/" + String(repeating: "a", count: 32) + ".cover"))
        XCTAssertFalse(BackupResources.persisted("covers/sub/" + String(repeating: "a", count: 32) + ".cover"))
    }

    func testThemeBackgroundAndFontPathsAreRebound() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/theme-resource-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("bg"), withIntermediateDirectories: true)
        let background = source.appendingPathComponent("bg/theme.png"), font = source.appendingPathComponent("custom.ttf")
        try Data("background".utf8).write(to: background)
        try Data("font-fixture".utf8).write(to: font)
        let config = try JSONSerialization.data(withJSONObject: [["backgroundImgPath": background.path]])
        let data = try await BackupExporter(database: AppDatabase.inMemory(), resourceDirectory: source).export(
            preferences: ["backgroundImageNight": .string(background.path), "coverFont": .string(font.path)],
            currentConfigurationFiles: ["themeConfig.json": config])
        let archive = try BackupArchive(data: data)
        XCTAssertEqual(archive.files["bg/theme.png"], Data("background".utf8))
        XCTAssertEqual(archive.files["coverFont.ttf"], Data("font-fixture".utf8))
        let db = try AppDatabase.inMemory()
        let report = try await BackupImporter(database: db, localDeviceID: "test", resourceDirectory: target).importArchive(data)
        XCTAssertEqual(report.preferences?["backgroundImageNight"], .string(target.appendingPathComponent("bg/theme.png").path))
        XCTAssertEqual(report.preferences?["coverFont"], .string(target.appendingPathComponent("font/coverFont.ttf").path))
        let restoredData = try await db.backupConfiguration(named: "themeConfig.json")
        let themes = try JSONSerialization.jsonObject(with: XCTUnwrap(restoredData)) as? [[String: String]]
        XCTAssertEqual(themes?.first?["backgroundImgPath"], target.appendingPathComponent("bg/theme.png").path)
    }

    func testResourcesRoundTripAndSelection() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/resource-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        let persisted = "covers/" + String(repeating: "a", count: 32) + ".cover"
        let paths = [persisted, "covers/custom.png", "readRecordCovers/record.png", "bg/used.png", "bg/unused.png"]
        for path in paths {
            let file = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: file)
        }
        let db = try AppDatabase.inMemory()
        var book = BookRow(); book.bookUrl = "book"; book.persistedCoverUrl = source.appendingPathComponent(persisted).path
        try await BookshelfRepository(database: db).upsert([book])
        var record = ReadRecordRow(); record.bookName = "book"; record.deviceId = "test"; record.coverUrl = source.appendingPathComponent(paths[2]).path
        try await ReadProgressRepository(database: db).upsert([record])
        let config = Data("[{\"bgType\":2,\"bgStr\":\"used.png\"}]".utf8)
        let outside = root.appendingPathComponent("outside.png")
        try Data("private".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("covers/link.png"), withDestinationURL: outside)
        let exporter = BackupExporter(database: db, resourceDirectory: source)

        let data = try await exporter.export(preferences: ["readRecordCover": .string(source.appendingPathComponent("covers/custom.png").path)], currentConfigurationFiles: ["readConfig.json": config], selection: .init(values: ["backupReadRecordCovers": false]))
        let archive = try BackupArchive(data: data)
        for path in paths.dropLast() { XCTAssertEqual(archive.files[path], Data(path.utf8), path) }
        XCTAssertNil(archive.files[paths.last!])
        XCTAssertNil(archive.files["covers/link.png"])
        let restored = try AppDatabase.inMemory()
        let report = try await BackupImporter(database: restored, localDeviceID: "test", resourceDirectory: target).importArchive(data)
        XCTAssertTrue(report.failures.isEmpty, "\(report.failures)")
        XCTAssertEqual(report.preferences?["readRecordCover"], .string(target.appendingPathComponent("covers/custom.png").path))
        for path in paths.dropLast() { XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent(path)), Data(path.utf8)) }
        let books = try await BookshelfRepository(database: restored).all()
        XCTAssertEqual(books.first?.persistedCoverUrl, target.appendingPathComponent(persisted).path)
        for (key, excluded) in [("backupPersistedCovers", persisted), ("backupOtherCovers", paths[1]), ("backupReadRecordCovers", paths[2]), ("backupBackgrounds", paths[3])] {
            let data = try await exporter.export(currentConfigurationFiles: ["readConfig.json": config], selection: .init(values: ["backupReadRecordCovers": false].merging([key: true]) { _, new in new }))
            let filtered = try BackupArchive(data: data)
            XCTAssertNil(filtered.files[excluded], key)
            if key == "backupPersistedCovers" {
                let books = try JSONDecoder().decode([BookRow].self, from: XCTUnwrap(filtered.files["bookshelf.json"]))
                XCTAssertNil(books.first?.persistedCoverUrl)
            }
            if key == "backupReadRecordCovers" {
                let records = try JSONDecoder().decode([ReadRecordRow].self, from: XCTUnwrap(filtered.files["readRecord.json"]))
                XCTAssertNil(records.first?.coverUrl)
            }

        }
        let ignored = root.appendingPathComponent("ignored")
        _ = try await BackupImporter(database: AppDatabase.inMemory(), localDeviceID: "test", resourceDirectory: ignored).importArchive(data, selection: .init(values: ["readConfig": true]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ignored.appendingPathComponent("bg/used.png").path))
        let guarded = root.appendingPathComponent("guarded")
        try FileManager.default.createDirectory(at: guarded.appendingPathComponent("covers"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: guarded.appendingPathComponent("covers/custom.png"), withDestinationURL: outside)
        do {
            _ = try await BackupImporter(database: AppDatabase.inMemory(), localDeviceID: "test", resourceDirectory: guarded).importArchive(data)
            XCTFail("A restore must not follow an existing symlink")
        } catch BackupArchiveError.unsafePath { }
        XCTAssertEqual(try Data(contentsOf: outside), Data("private".utf8))

    }
}

extension BackupResourceTests {
    func testExportKeepsImportedReadingBackgroundConfigurations() async throws {
        let db = try AppDatabase.inMemory()
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/imported-bg-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bg"), withIntermediateDirectories: true)
        for name in ["day.png", "night.png", "ink.png"] {
            try Data(name.utf8).write(to: root.appendingPathComponent("bg/" + name))
        }
        let read = Data("[{\"name\":\"day\",\"bgType\":2,\"bgStr\":\"day.png\"},{\"name\":\"night\",\"bgTypeNight\":2,\"bgStrNight\":\"night.png\"}]".utf8)
        let share = Data("{\"bgTypeEInk\":2,\"bgStrEInk\":\"ink.png\"}".utf8)
        try await db.write { connection in
            for (name, data) in [("readConfig.json", read), ("shareReadConfig.json", share)] {
                try connection.execute(sql: "INSERT INTO backup_files (name, data) VALUES (?, ?)", arguments: [name, data])
            }
        }
        let archive = try BackupArchive(data: await BackupExporter(database: db, resourceDirectory: root).export())
        for name in ["day.png", "night.png", "ink.png"] { XCTAssertEqual(archive.files["bg/" + name], Data(name.utf8)) }
        let configurations = try JSONSerialization.jsonObject(with: XCTUnwrap(archive.files["readConfig.json"])) as! [[String: Any]]
        XCTAssertEqual(configurations.count, 2)
        XCTAssertEqual(configurations.first?["bgType"] as? Int, 2)
        let shared = try JSONSerialization.jsonObject(with: XCTUnwrap(archive.files["shareReadConfig.json"])) as! [String: Any]
        XCTAssertEqual(shared["bgTypeEInk"] as? Int, 2)
    }

    func testExportAppliesIgnoreKeysBeforeWritingArchive() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/ignore-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let font = root.appendingPathComponent("font.ttf")
        try Data("font".utf8).write(to: font)
        let archive = try BackupArchive(data: await BackupExporter(database: AppDatabase.inMemory(), resourceDirectory: root).export(
            preferences: ["coverFont": .string(font.path), "coverShowName": .boolean(false), "readStyleSelect": .int(2), "colorAccent": .int(123), "fontScale": .int(12)],
            selection: .init(values: ["coverConfig": true, "readConfig": true, "themeConfig": true])))
        for name in ["coverFont.ttf", "readConfig.json", "shareReadConfig.json", "themeConfig.json"] { XCTAssertNil(archive.files[name], name) }
        let preferences = try AndroidPreferencesXML.decode(XCTUnwrap(archive.files["config.xml"]))
        for key in ["coverFont", "coverShowName", "readStyleSelect", "colorAccent"] { XCTAssertNil(preferences[key], key) }
        XCTAssertEqual(preferences["fontScale"], .int(12))
    }

    func testRestorePreservesPostScriptFontName() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/font-name-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try await BackupExporter(database: AppDatabase.inMemory()).export(preferences: ["coverFont": .string("TimesNewRomanPSMT")])
        let report = try await BackupImporter(database: AppDatabase.inMemory(), localDeviceID: "test", resourceDirectory: root).importArchive(data)
        XCTAssertEqual(report.preferences?["coverFont"], .string("TimesNewRomanPSMT"))
    }

    func testCoverFontReferenceDistinguishesNamesAndFilePaths() {
        XCTAssertEqual(CoverFontReference(""), .none)
        XCTAssertEqual(CoverFontReference("TimesNewRomanPSMT"), .name("TimesNewRomanPSMT"))
        XCTAssertEqual(CoverFontReference("file:///fonts/book.ttf"), .file(URL(fileURLWithPath: "/fonts/book.ttf")))
        XCTAssertEqual(CoverFontReference("/fonts/book.otf"), .file(URL(fileURLWithPath: "/fonts/book.otf")))
        XCTAssertEqual(CoverFontReference("fonts/book.ttf"), .file(URL(fileURLWithPath: "fonts/book.ttf")))
        XCTAssertEqual(CoverFontReference("book.ttc"), .file(URL(fileURLWithPath: "book.ttc")))
    }
}
