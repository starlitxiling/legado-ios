import XCTest
import LegadoCore
@testable import SettingsBackupCheck

@MainActor
final class BackupReviewFixTests: XCTestCase {
    private func fixture() throws -> (UserDefaults, BackupPreferences, AppDatabase, URL) {
        let name = "BackupReviewFixTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/tmp/" + name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        return (defaults, BackupPreferences(defaults: defaults, deviceModel: { "TestPhone1,1" }), try .inMemory(), directory)
    }

    func testCurrentReaderSettingsReplaceArchivedCopyOnEveryBackup() async throws {
        let (defaults, preferences, database, directory) = try fixture()
        let stale = Data("[{\"textSize\":12}]".utf8)
        try await database.write { db in
            try db.execute(sql: "INSERT INTO backup_files (name, data) VALUES (?, ?)", arguments: ["readConfig.json", stale])
        }
        let model = BackupViewModel(database: database, localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        preferences.set("themeMode", .string("2"))
        for size in [26, 31] {
            defaults.set(size, forKey: "textSize")
            defaults.set(true, forKey: "isNightTheme")
            defaults.set("#123456", forKey: "bgStr")
            defaults.set(17, forKey: "autoReadSpeed")
            defaults.set(true, forKey: "hideStatusBar")
            preferences.set("colorBackgroundNight", .int(Int32(bitPattern: 0xFFABCDEF)))
            preferences.saveTheme(name: "当前主题", night: true)
            await model.createBackup(upload: false, now: Date(timeIntervalSince1970: 100))
            XCTAssertNil(model.errorMessage)
            let archive = try BackupArchive(data: Data(contentsOf: XCTUnwrap(model.exportedFile)))
            let configs = try JSONSerialization.jsonObject(with: XCTUnwrap(archive.files["readConfig.json"])) as! [[String: Any]]
            let xml = try AndroidPreferencesXML.decode(XCTUnwrap(archive.files["config.xml"]))
            XCTAssertEqual(xml["autoReadSpeed"], .int(17))
            XCTAssertEqual(xml["hideStatusBar"], .boolean(true))
            XCTAssertEqual(configs.first?["textSize"] as? Int, size, "必须序列化当前阅读配置")
            XCTAssertEqual(configs.first?["bgStr"] as? String, "#123456")
            XCTAssertNotNil(archive.files["shareReadConfig.json"])
            XCTAssertNotNil(archive.files["themeConfig.json"])
            let themes = try JSONSerialization.jsonObject(with: XCTUnwrap(archive.files["themeConfig.json"])) as! [[String: Any]]
            let theme = try XCTUnwrap(themes.first { $0["themeName"] as? String == "当前主题" })
            XCTAssertEqual(theme["isNightTheme"] as? Bool, true)
            XCTAssertEqual(theme["backgroundColor"] as? String, "#FFABCDEF")
        }
    }

    func testMissingDeviceNameUsesModelAndSurvivesReload() throws {
        let (_, preferences, _, _) = try fixture()
        XCTAssertEqual(preferences.string("webDavDeviceName"), "TestPhone1,1", "缺省设备名必须是设备型号")
        preferences.set("threadCount", .int(7))
        preferences.reload()
        XCTAssertFalse(preferences.string("webDavDeviceName").isEmpty)
        preferences.set("webDavDeviceName", .string(""))
        XCTAssertEqual(preferences.string("webDavDeviceName"), "", "显式空设备名仍允许无后缀")
    }

    func testDefaultModelAppearsInExportedFileName() async throws {
        let (_, preferences, database, directory) = try fixture()
        preferences.set("onlyLatestBackup", .boolean(false))
        let model = BackupViewModel(database: database, localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        await model.createBackup(upload: false, now: Date(timeIntervalSince1970: 172800))
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(try XCTUnwrap(model.exportedFile).lastPathComponent.hasSuffix("-TestPhone1,1.zip"))
    }

    func testWaitingAutomaticBackupRechecksIntervalAfterLock() async throws {
        let (_, preferences, database, directory) = try fixture()
        let client = HeldBackupClient()
        let first = BackupViewModel(database: database, localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        let second = BackupViewModel(database: database, localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        let credentials = WebDavCredentials(baseURL: URL(string: "https://example.invalid/")!, username: "u", password: "p")
        try first.configure(credentials: credentials, httpClient: client)
        try second.configure(credentials: credentials, httpClient: client)
        let date = Date(timeIntervalSince1970: 172800)
        let firstTask = Task { await first.automaticBackup(now: date) }
        await client.waitUntilUploading()
        let secondTask = Task { await second.automaticBackup(now: date) }
        await client.releaseUpload()
        await firstTask.value; await secondTask.value
        XCTAssertNil(second.exportedFile)
        XCTAssertNil(second.errorMessage)
        XCTAssertEqual(preferences.lastBackup, 172800000)
    }

    func testCancelledWaiterDoesNotWriteOrLeakLock() async throws {
        let (_, preferences, database, directory) = try fixture()
        let client = HeldBackupClient()
        let first = BackupViewModel(database: database, localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        let second = BackupViewModel(database: database, localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        try first.configure(credentials: WebDavCredentials(baseURL: URL(string: "https://example.invalid/")!, username: "u", password: "p"), httpClient: client)
        let date = Date(timeIntervalSince1970: 172800)
        let held = Task { await first.createBackup(upload: true, now: date) }
        await client.waitUntilUploading()
        let waiting = Task { await second.createBackup(upload: false, now: date) }
        while !second.isBusy { await Task.yield() }
        waiting.cancel()
        await waiting.value
        XCTAssertNil(second.exportedFile)
        XCTAssertNotNil(second.errorMessage)
        await client.releaseUpload()
        await held.value
        await second.createBackup(upload: false, now: date)
        XCTAssertNotNil(second.exportedFile)
        XCTAssertNil(second.errorMessage)
    }

    func testOldPreferencesResetMissingAutomaticBackupFields() async throws {
        let (_, preferences, database, directory) = try fixture()
        preferences.set("autoBackup", .boolean(false))
        preferences.set("autoBackupWebDav", .boolean(false))
        preferences.set("autoBackupIntervalDays", .int(20))
        let oldBackup = try await BackupExporter(database: database, now: { Date(timeIntervalSince1970: 100) })
            .export(preferences: ["themeMode": .string("2")])
        let model = BackupViewModel(database: database, localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        await model.restoreLocalData(oldBackup)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(preferences.boolean("autoBackup"))
        XCTAssertTrue(preferences.boolean("autoBackupWebDav"))
        XCTAssertEqual(preferences.integer("autoBackupIntervalDays"), 1)
        preferences.apply(["autoBackup": .boolean(false), "autoBackupWebDav": .boolean(false), "autoBackupIntervalDays": .int(5)])
        XCTAssertFalse(preferences.boolean("autoBackup"))
        XCTAssertFalse(preferences.boolean("autoBackupWebDav"))
        XCTAssertEqual(preferences.integer("autoBackupIntervalDays"), 5)
    }

    func testVideoRestoreMergesAndEmptyMapPreservesLocalKeys() async throws {
        let (_, preferences, database, directory) = try fixture()
        preferences.videoSnapshot = ["localOnly": .int(7), "shared": .string("old")]
        let model = BackupViewModel(database: database, localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        for incoming: [String: AndroidPreferenceValue] in [["shared": .string("new")], [:]] {
            let data = try await BackupExporter(database: database, now: { Date(timeIntervalSince1970: 100) }).export(videoPreferences: incoming)
            await model.restoreLocalData(data)
            XCTAssertEqual(preferences.videoSnapshot["localOnly"], .int(7))
            XCTAssertEqual(preferences.videoSnapshot["shared"], .string("new"))
        }
    }

    func testAutomaticManualAndRestoreShareOneLock() async throws {
        let (_, preferences, database, directory) = try fixture()
        let client = HeldBackupClient()
        let first = BackupViewModel(database: database, localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        let second = BackupViewModel(database: database, localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        let third = BackupViewModel(database: database, localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        let restoreData = try await BackupExporter(database: database, now: { Date(timeIntervalSince1970: 100) }).export(preferences: ["themeMode": .string("2")])
        try first.configure(credentials: WebDavCredentials(baseURL: URL(string: "https://example.invalid/")!, username: "u", password: "p"), httpClient: client)
        let automatic = Task { await first.automaticBackup(now: Date(timeIntervalSince1970: 172800)) }
        await client.waitUntilUploading()
        let manualFinished = expectation(description: "手动备份应等待自动备份")
        let restoreFinished = expectation(description: "恢复应等待自动备份")
        manualFinished.isInverted = true; restoreFinished.isInverted = true
        let manual = Task { await second.createBackup(upload: false, now: Date(timeIntervalSince1970: 172800)); manualFinished.fulfill() }
        let restore = Task { await third.restoreLocalData(restoreData); restoreFinished.fulfill() }
        await fulfillment(of: [manualFinished, restoreFinished], timeout: 0.1)
        XCTAssertEqual(preferences.string("themeMode"), "0")
        await client.releaseUpload()
        await automatic.value; await manual.value; await restore.value
        XCTAssertNil(first.errorMessage); XCTAssertNil(second.errorMessage); XCTAssertNil(third.errorMessage)
        XCTAssertEqual(preferences.string("themeMode"), "2")
    }
}

private actor HeldBackupClient: HttpClient {
    private var entered = false
    private var started: CheckedContinuation<Void, Never>?
    private var held: CheckedContinuation<Void, Never>?
    func waitUntilUploading() async {
        if !entered { await withCheckedContinuation { started = $0 } }
    }
    func releaseUpload() { held?.resume(); held = nil }
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        if request.method == "PUT" {
            await withCheckedContinuation { continuation in
                held = continuation; entered = true; started?.resume(); started = nil
            }
        }
        return HttpResponse(status: request.method == "PROPFIND" ? 207 : 201, finalURL: request.url)
    }
}

extension BackupReviewFixTests {
    func testCurrentBackupPreservesImportedBackgroundsAndAdditionalStyles() async throws {
        let (defaults, preferences, database, directory) = try fixture()
        let read = Data("[{\"textSize\":12,\"bgType\":2,\"bgStr\":\"day.png\"},{\"name\":\"other\",\"bgTypeNight\":2,\"bgStrNight\":\"night.png\"}]".utf8)
        let share = Data("{\"bgTypeEInk\":2,\"bgStrEInk\":\"ink.png\"}".utf8)
        try await database.write { db in
            for (name, data) in [("readConfig.json", read), ("shareReadConfig.json", share)] {
                try db.execute(sql: "INSERT INTO backup_files (name, data) VALUES (?, ?)", arguments: [name, data])
            }
        }
        defaults.set(31, forKey: "textSize")
        let model = BackupViewModel(database: database, localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        await model.createBackup(upload: false)
        XCTAssertNil(model.errorMessage)
        let archive = try BackupArchive(data: Data(contentsOf: XCTUnwrap(model.exportedFile)))
        let styles = try JSONSerialization.jsonObject(with: XCTUnwrap(archive.files["readConfig.json"])) as! [[String: Any]]
        XCTAssertEqual(styles.count, 2)
        XCTAssertEqual(styles.first?["textSize"] as? Int, 31)
        XCTAssertEqual(styles.first?["bgType"] as? Int, 2)
        XCTAssertEqual(styles.first?["bgStr"] as? String, "day.png")
        let shared = try JSONSerialization.jsonObject(with: XCTUnwrap(archive.files["shareReadConfig.json"])) as! [String: Any]
        XCTAssertEqual(shared["bgStrEInk"] as? String, "ink.png")
        defaults.set(1, forKey: "readStyleSelect")
        defaults.set(35, forKey: "textSize")
        await model.createBackup(upload: false)
        let selectedArchive = try BackupArchive(data: Data(contentsOf: XCTUnwrap(model.exportedFile)))
        let xml = try AndroidPreferencesXML.decode(XCTUnwrap(selectedArchive.files["config.xml"]))
        XCTAssertEqual(xml["readStyleSelect"], .int(1))
        let selectedStyles = try JSONSerialization.jsonObject(with: XCTUnwrap(selectedArchive.files["readConfig.json"])) as! [[String: Any]]
        XCTAssertEqual(selectedStyles.last?["textSize"] as? Int, 35)
        XCTAssertEqual(selectedStyles.first?["textSize"] as? Int, 12)
    }
}
