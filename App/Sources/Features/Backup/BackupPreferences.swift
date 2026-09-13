import Foundation
import Observation
import LegadoCore
import Darwin

@Observable
@MainActor
final class AppPreferences {
    let defaults: UserDefaults
    var configurationRevision = 0
    private let deviceModel: () -> String
    private(set) var snapshot: [String: AndroidPreferenceValue]
    var videoSnapshot: [String: AndroidPreferenceValue] {
        get { defaults.data(forKey: "Legado.videoPreferencesXML").flatMap { try? AndroidPreferencesXML.decode($0) } ?? [:] }
        set {
            let merged = videoSnapshot.merging(newValue) { _, incoming in incoming }
            defaults.set(AndroidPreferencesXML.encode(merged), forKey: "Legado.videoPreferencesXML")
        }
    }

    init(defaults: UserDefaults = .standard, deviceModel: @escaping () -> String = BackupPreferences.systemDeviceModel) {
        self.defaults = defaults
        self.deviceModel = deviceModel
        snapshot = Self.settingDefaults
        if let data = defaults.data(forKey: "Legado.androidPreferencesXML"), let saved = try? AndroidPreferencesXML.decode(data) {
            snapshot.merge(saved) { _, value in value }
        }
        if let device = defaults.string(forKey: "webDavDeviceName") { snapshot["webDavDeviceName"] = .string(device) }
        reload()
    }

    var lastBackup: Int64 {
        get { (defaults.object(forKey: "Legado.lastBackup") as? NSNumber)?.int64Value ?? 0 }
        set { defaults.set(newValue, forKey: "Legado.lastBackup") }
    }

    func string(_ key: String) -> String {
        if case .string(let value) = snapshot[key] { return value }
        return key == "webDavDeviceName" ? deviceModel() : ""
    }
    func boolean(_ key: String) -> Bool { if case .boolean(let value) = snapshot[key] { return value }; return false }
    func integer(_ key: String) -> Int { if case .int(let value) = snapshot[key] { return Int(value) }; return 0 }

    func set(_ key: String, _ value: AndroidPreferenceValue) {
        reload()
        snapshot[key] = value
        defaults.set(AndroidPreferencesXML.encode(snapshot), forKey: "Legado.androidPreferencesXML")
        switch value {
        case .string(let value): defaults.set(value, forKey: key)
        case .int(let value): defaults.set(Int(value), forKey: key)
        case .boolean(let value): defaults.set(value, forKey: key)
        case .long(let value): defaults.set(value, forKey: key)
        case .float(let value): defaults.set(value, forKey: key)
        case .stringSet(let value): defaults.set(Array(value).sorted(), forKey: key)
        }
    }

    func reload() {
        var values = Self.settingDefaults
        if let data = defaults.data(forKey: "Legado.androidPreferencesXML"), let saved = try? AndroidPreferencesXML.decode(data) {
            values.merge(saved) { _, value in value }
        }
        for (key, expected) in values {
            guard let raw = defaults.object(forKey: key) else { continue }
            switch (expected, raw) {
            case (.string, let value as String): values[key] = .string(value)
            case (.boolean, let value as NSNumber): values[key] = .boolean(value.boolValue)
            case (.int, let value as NSNumber): values[key] = .int(Int32(clamping: value.int64Value))
            case (.long, let value as NSNumber): values[key] = .long(value.int64Value)
            case (.float, let value as NSNumber): values[key] = .float(value.floatValue)
            case (.stringSet, let value as [String]): values[key] = .stringSet(Set(value))
            default: break
            }
        }
        if let device = defaults.string(forKey: "webDavDeviceName") { values["webDavDeviceName"] = .string(device) }
        snapshot = values
    }

    func apply(_ incoming: [String: AndroidPreferenceValue]) {
        let selection = backupSelection
        for key in ["autoBackup", "autoBackupWebDav", "autoBackupIntervalDays"] where incoming[key] == nil {
            if let value = AndroidBackupPreferences.defaults[key] { set(key, value) }
        }
        let missingDefaults = ["showReadTitleChapterNameOnly": false, "showExploreCategories": false,
                               "coverTitleAdaptive": true, "coverCustomFontSize": false,
                               "readRecordSimpleLayout": true, "readRecordUseDays": false,
                               "readRecordShowSeconds": true, "readRecordFixedCard": true,
                               "mangaRightToLeft": false]
        for (key, value) in missingDefaults where incoming[key] == nil && selection.allowsPreference(key) {
            set(key, .boolean(value))
        }
        for (key, value) in incoming where selection.allowsPreference(key) {
            if let expected = Self.settingDefaults[key] {
                switch (expected, value) {
                case (.string, .string), (.boolean, .boolean), (.int, .int), (.long, .long), (.float, .float), (.stringSet, .stringSet): break
                default: continue
                }
            }
            set(key, value)
        }
        let removed = ["coverFont", "readRecordCover", "readRecordCoverDark"].filter {
            incoming[$0] == nil && selection.allowsPreference($0)
        }
        if !removed.isEmpty {
            for key in removed {
                defaults.removeObject(forKey: key)
                snapshot.removeValue(forKey: key)
            }
            defaults.set(AndroidPreferencesXML.encode(snapshot), forKey: "Legado.androidPreferencesXML")
            reload()
        }
    }

    func currentConfigurationFiles(retainedFiles: [String: Data] = [:]) throws -> [String: Data] {
        var files = try CurrentBackupConfiguration.files(defaults: defaults, preferences: self, retainedFiles: retainedFiles)
        files["themeConfig.json"] = try JSONEncoder().encode(themes)
        return files
    }

    func currentPreferenceSnapshot() -> [String: AndroidPreferenceValue] {
        var values = snapshot
        let settings = ReaderSettings.load(from: defaults)
        values["autoReadSpeed"] = .int(Int32(settings.autoReadSpeed))
        values["hideStatusBar"] = .boolean(settings.hideStatusBar)
        values["readStyleSelect"] = .int(Int32(clamping: defaults.integer(forKey: "readStyleSelect")))
        return values
    }

    nonisolated private static func systemDeviceModel() -> String {
        var value = utsname()
        guard uname(&value) == 0 else { return "iOS" }
        return withUnsafeBytes(of: &value.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

typealias BackupPreferences = AppPreferences
