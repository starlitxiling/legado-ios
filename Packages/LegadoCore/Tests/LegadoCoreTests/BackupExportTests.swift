import XCTest
@testable import LegadoCore

final class BackupExportTests: XCTestCase {
    func testDefaultBackupOmitsOptInStateAndAbsentConfiguration() async throws {
        let database = try AppDatabase.inMemory()
        let data = try await BackupExporter(database: database).export()
        let files = try BackupArchive(data: data).files
        XCTAssertNil(files["cookies.json"])
        XCTAssertNil(files["runtimeSourceCache.json"])
        XCTAssertNotNil(files["readConfig.json"])
        XCTAssertNotNil(files["shareReadConfig.json"])
        XCTAssertNotNil(files["themeConfig.json"])
    }
    func testCurrentConfigurationOverridesArchivedConfiguration() async throws {
        let database = try AppDatabase.inMemory()
        let config = Data("[{\"name\":\"自定义主题\"}]".utf8)
        try await database.write { db in
            try db.execute(sql: "INSERT INTO backup_files (name, data) VALUES (?, ?)", arguments: ["themeConfig.json", config])
        }
        let current = Data("[{\"themeName\":\"当前主题\"}]".utf8)
        let data = try await BackupExporter(database: database).export(currentConfigurationFiles: ["themeConfig.json": current])
        XCTAssertEqual(try BackupArchive(data: data).files["themeConfig.json"], current)
    }
    func testStaleSyncDoesNotOverwriteNewReadingOrBookMetadata() async throws {
        let database = try AppDatabase.inMemory()
        var book = BookRow(); book.bookUrl = "https://example.invalid/book"; book.name = "原书名"
        try await BookshelfRepository(database: database).upsert(book)
        var remote = book; remote.durChapterIndex = 9; remote.syncTime = 200
        var newer = book; newer.durChapterIndex = 5; newer.durChapterTime = 300; newer.name = "新书名"
        try await BookshelfRepository(database: database).upsert(newer)
        try await BookProgressSync.save(remote, replacing: book, database: database)
        let rows = try await BookshelfRepository(database: database).all()
        XCTAssertEqual(rows.first?.name, "新书名")
        XCTAssertEqual(rows.first?.durChapterIndex, 5)
        XCTAssertEqual(rows.first?.syncTime, 0)
    }
    func testCustomDictionaryRoundTrip() async throws {
        let database = try AppDatabase.inMemory()
        let custom = DictRule(name: "自定义词典", urlRule: "https://example.invalid/{{key}}", showRule: "body", enabled: false, sortNumber: 9)
        try await DictRuleRepository(database: database).save(custom)
        let archive = try await BackupExporter(database: database).export()
        let restored = try AppDatabase.inMemory()
        let report = try await BackupImporter(database: restored, localDeviceID: "local").importArchive(archive)
        XCTAssertNotNil(report.importedCounts["dictRule.json"])
        let rules = try await DictRuleRepository(database: restored).list()
        XCTAssertTrue(rules.contains(custom))
    }
    func testArchiveRoundTripAndAndroidNames() async throws {
        let database = try AppDatabase.inMemory()
        var book = BookRow(); book.bookUrl = "https://example.invalid/book"; book.name = "书"; book.author = "作者"
        book.readConfig = "{\"reverseToc\":true}"
        try await BookshelfRepository(database: database).upsert(book)
        let exporter = BackupExporter(database: database, now: { Date(timeIntervalSince1970: 0) }, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(exporter.fileName(), "backup1970-01-01.zip")
        XCTAssertEqual(exporter.fileName(deviceName: "a/b"), "backup1970-01-01-a_b.zip")
        let output = try await exporter.export(preferences: ["themeMode": .string("0")])
        let archive = try BackupArchive(data: output)
        for name in ["bookSource.json", "bookshelf.json", "replaceRule.json", "readRecord.json", "bookmark.json", "rssSources.json", "rssStar.json", "txtTocRule.json", "dictRule.json", "httpTTS.json", "config.xml", "videoConfig.xml"] {
            XCTAssertNotNil(archive.files[name], name)
        }
        XCTAssertEqual(try AndroidPreferencesXML.decode(archive.files["config.xml"]!)["themeMode"], .string("0"))
        let restored = try AppDatabase.inMemory()
        let report = try await BackupImporter(database: restored, localDeviceID: "local").importArchive(output)
        XCTAssertTrue(report.failures.isEmpty, "\(report.failures)")
        XCTAssertEqual(report.preferences?["themeMode"], .string("0"))
        let rows = try await BookshelfRepository(database: restored).all()
        XCTAssertEqual(rows.first?.name, book.name)
        let readConfig = try JSONSerialization.jsonObject(with: Data(rows.first!.readConfig!.utf8)) as! [String: Any]
        XCTAssertEqual(readConfig["reverseToc"] as? Bool, true)
    }

    func testPreferenceTypesEscapingAndAndroidKeys() throws {
        let values: [String: AndroidPreferenceValue] = ["s": .string("<&\"中文"), "b": .boolean(true), "i": .int(2), "l": .long(9999999999), "f": .float(1.5), "set": .stringSet(["a", "b"])]
        XCTAssertEqual(try AndroidPreferencesXML.decode(AndroidPreferencesXML.encode(values)), values)
        let keys = ["themeMode", "language", "preDownloadNum", "threadCount", "bookshelfSort", "autoBackup", "autoBackupWebDav", "autoBackupIntervalDays", "syncBookProgress", "onlyLatestBackup"]
        let defaults = AndroidBackupPreferences.defaults
        for key in keys { XCTAssertNotNil(defaults[key], key) }
        XCTAssertEqual(defaults["preDownloadNum"], .int(2))
        XCTAssertEqual(defaults["threadCount"], .int(32))
        XCTAssertThrowsError(try AndroidPreferencesXML.decode(Data("<map><int name=\"x\" value=\"wrong\"/></map>".utf8)))
    }

    func testAutomaticBackupInterval() {
        XCTAssertFalse(BackupExporter.shouldBackup(enabled: false, now: 86400000, lastBackup: 0, intervalDays: 1))
        XCTAssertFalse(BackupExporter.shouldBackup(enabled: true, now: 86399999, lastBackup: 0, intervalDays: 1))
        XCTAssertTrue(BackupExporter.shouldBackup(enabled: true, now: 86400000, lastBackup: 0, intervalDays: 1))
        XCTAssertFalse(BackupExporter.shouldBackup(enabled: true, now: 0, lastBackup: 1, intervalDays: 1))
    }

    func testUploadUsesOnlyFakeClient() async throws {
        let replay = ReplayHttpClient()
        let client = WebDavClient(baseURL: URL(string: "https://example.invalid/dav/")!, username: "u", password: "p", httpClient: replay)
        let directory = try client.url(path: "legado/")
        let file = try client.url(path: "legado/backup1970-01-01.zip")
        await replay.enqueue(url: directory, method: "PROPFIND", response: HttpResponse(status: 404, finalURL: directory))
        await replay.enqueue(url: directory, method: "MKCOL", response: HttpResponse(status: 201, finalURL: directory))
        await replay.enqueue(url: file, method: "PUT", response: HttpResponse(status: 201, finalURL: file))
        try await WebDavBackupUploader(client: client).upload(Data("zip".utf8), fileName: "backup1970-01-01.zip")
        let requests = await replay.requests
        XCTAssertEqual(requests.map(\.method), ["PROPFIND", "MKCOL", "PUT"])
        XCTAssertEqual(requests.last?.url, file)
        XCTAssertEqual(requests.last?.body, Data("zip".utf8))
    }

    func testExistingCollectionSkipsCreationAndUploadFailurePropagates() async throws {
        let replay = ReplayHttpClient()
        let client = WebDavClient(baseURL: URL(string: "https://example.invalid/dav/")!, username: "u", password: "p", httpClient: replay)
        let directory = try client.url(path: "legado/")
        let file = try client.url(path: "legado/backup1970-01-01.zip")
        await replay.enqueue(url: directory, method: "PROPFIND", response: HttpResponse(status: 207, finalURL: directory))
        await replay.enqueue(url: file, method: "PUT", response: HttpResponse(status: 500, finalURL: file))
        do {
            try await WebDavBackupUploader(client: client).upload(Data(), fileName: "backup1970-01-01.zip")
            XCTFail("上传失败必须向调用方传播")
        } catch WebDavError.httpStatus(500) {}
        let requests = await replay.requests
        XCTAssertEqual(requests.map(\.method), ["PROPFIND", "PUT"])
        XCTAssertNil(requests.last?.headers["If-None-Match"])
    }

    func testProgressJSONUploadAndDownloadUseFakeClient() async throws {
        let replay = ReplayHttpClient()
        let client = WebDavClient(baseURL: URL(string: "https://example.invalid/dav/")!, username: "u", password: "p", httpClient: replay)
        var book = BookRow(); book.name = "a+b"; book.author = "c/d"; book.durChapterIndex = 3
        let root = try client.url(path: "legado/")
        let directory = try client.url(path: "legado/bookProgress/")
        let file = URL(string: "https://example.invalid/dav/legado/bookProgress/a%2Bb_c_d.json")!
        for url in [root, directory] {
            await replay.enqueue(url: url, method: "PROPFIND", response: HttpResponse(status: 207, finalURL: url))
        }
        await replay.enqueue(url: file, method: "PUT", response: HttpResponse(status: 201, finalURL: file))
        let sync = BookProgressSync(client: client)
        let uploaded = try await sync.upload(book, now: 10)
        XCTAssertEqual(uploaded.syncTime, 10)
        let requests = await replay.requests
        let body = try JSONSerialization.jsonObject(with: requests.last!.body!) as! [String: Any]
        XCTAssertEqual(Set(body.keys), Set(["name", "author", "durChapterIndex", "durChapterPos", "durChapterTime"]))
        XCTAssertEqual(requests.last?.headers["Content-Type"], "application/json")
        await replay.enqueue(url: file, method: "PROPFIND", response: HttpResponse(status: 404, finalURL: file))
        let unchanged = try await sync.download(uploaded, now: 30)
        XCTAssertEqual(unchanged.syncTime, 10)
    }

    func testPreferencesRejectEntitiesAndRetainUnknownKeys() throws {
        XCTAssertThrowsError(try AndroidPreferencesXML.decode(Data("<!DOCTYPE map [<!ENTITY x 'expansion'>]><map><string name='x'>&x;</string></map>".utf8)))
        let values: [String: AndroidPreferenceValue] = ["future": .long(42), "themeMode": .string("3")]
        XCTAssertEqual(try AndroidPreferencesXML.decode(AndroidPreferencesXML.encode(values)), values)
    }

    func testProgressMergeRequiresRemoteModificationAndForwardPosition() {
        var book = BookRow(); book.name = "书"; book.author = "作者"; book.syncTime = 100; book.durChapterIndex = 3; book.durChapterPos = 10
        var remote = BookProgress(book: book); remote.durChapterIndex = 4; remote.durChapterTime = 50
        XCTAssertEqual(BookProgressSync.merge(book: book, remote: remote, remoteModified: 100, now: 300).durChapterIndex, 3)
        XCTAssertEqual(BookProgressSync.merge(book: book, remote: remote, remoteModified: 101, now: 300).syncTime, 300)
        remote.durChapterIndex = 2; remote.durChapterTime = 999
        XCTAssertEqual(BookProgressSync.merge(book: book, remote: remote, remoteModified: 101, now: 300).durChapterIndex, 3)
        remote.durChapterIndex = 3; remote.durChapterPos = 11
        XCTAssertEqual(BookProgressSync.merge(book: book, remote: remote, remoteModified: 101, now: 300).durChapterPos, 11)
    }
}
