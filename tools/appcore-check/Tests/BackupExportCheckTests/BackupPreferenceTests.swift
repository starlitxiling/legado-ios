import XCTest
import LegadoCore
@testable import SettingsBackupCheck

@MainActor
final class BackupPreferenceTests: XCTestCase {
    func testLocalBackupAndFailedUploadDoNotAdvanceSuccessfulTimestamp() async throws {
        let suite = "B13." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = BackupPreferences(defaults: defaults)
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/tmp/" + suite)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BackupViewModel(database: try AppDatabase.inMemory(), localDeviceID: "test", resourceDirectory: nil, preferences: preferences, exportDirectory: directory)
        await model.createBackup(upload: false, now: Date(timeIntervalSince1970: 100))
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.exportedFile?.lastPathComponent, "backup.zip")
        XCTAssertEqual(preferences.lastBackup, 100000)
        let archive = try BackupArchive(data: Data(contentsOf: model.exportedFile!))
        XCTAssertNotNil(archive.files["config.xml"])
        await model.createBackup(upload: true, now: Date(timeIntervalSince1970: 200))
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(preferences.lastBackup, 100000)
        XCTAssertFalse(model.isBusy)
    }
    func testPreferencesRoundTripRetainsAndroidTypes() throws {
        let suite = "B13." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = BackupPreferences(defaults: defaults)
        preferences.set("themeMode", .string("3"))
        preferences.set("threadCount", .int(8))
        let restored = BackupPreferences(defaults: defaults)
        XCTAssertEqual(restored.string("themeMode"), "3")
        XCTAssertEqual(restored.integer("threadCount"), 8)
        let xml = AndroidPreferencesXML.encode(restored.snapshot)
        XCTAssertTrue(String(decoding: xml, as: UTF8.self).contains("<int name=\"threadCount\" value=\"8\""))
        restored.apply(["themeMode": .string("2"), "threadCount": .string("invalid")])
        XCTAssertEqual(restored.string("themeMode"), "2")
        XCTAssertEqual(restored.integer("threadCount"), 8)
    }
}
