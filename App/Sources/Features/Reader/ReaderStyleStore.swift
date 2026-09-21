import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class ReaderStyleStore {
    private(set) var styles: [ReadBookConfig] = []
    private(set) var selected = 0
    private(set) var sharedLayout = false
    private var shared = ReadBookConfig()
    private let database: AppDatabase
    private let defaults: UserDefaults

    init(database: AppDatabase, defaults: UserDefaults = .standard) {
        self.database = database; self.defaults = defaults
    }

    var current: ReadBookConfig {
        guard styles.indices.contains(selected) else { return ReadBookConfig() }
        return sharedLayout ? Self.copyColors(from: styles[selected], into: shared) : styles[selected]
    }

    func load() async throws {
        let saved = try await database.backupConfiguration(named: "readConfig.json")
        var loaded = try saved.map(ReadBookConfig.importThemes) ?? ReadBookConfig.bundledStyles()
        guard !loaded.isEmpty else { throw ReaderStyleError.empty }
        selected = min(max(0, defaults.integer(forKey: "readStyleSelect")), loaded.count - 1)
        if saved == nil {
            var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded[selected])) as! [String: Any]
            for key in fields.keys { if let value = defaults.object(forKey: key) { fields[key] = value } }
            loaded[selected] = try JSONDecoder().decode(ReadBookConfig.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        styles = loaded.map { ReaderSettings(configuration: $0).normalized.configuration }
        let sharedData = try await database.backupConfiguration(named: "shareReadConfig.json")
        shared = try sharedData.map { try JSONDecoder().decode(ReadBookConfig.self, from: $0) } ?? styles[min(5, styles.count - 1)]
        sharedLayout = defaults.bool(forKey: "shareLayout")
        synchronizeSettings()
    }

    func select(_ index: Int) async throws {
        guard styles.indices.contains(index) else { throw ReaderStyleError.invalidSelection }
        selected = index
        try await persist()
    }

    func setSharedLayout(_ enabled: Bool) async throws {
        sharedLayout = enabled
        try await persist()
    }

    func update(_ configuration: ReadBookConfig) async throws {
        guard styles.indices.contains(selected) else { throw ReaderStyleError.invalidSelection }
        let normalized = ReaderSettings(configuration: configuration).normalized.configuration
        if sharedLayout {
            shared = normalized
            styles[selected] = Self.copyColors(from: normalized, into: styles[selected])
        } else { styles[selected] = normalized }
        try await persist()
    }

    func importStyles(_ data: Data) async throws {
        let imported = try ReadBookConfig.importThemes(data)
        guard !imported.isEmpty else { throw ReaderStyleError.empty }
        selected = styles.count
        styles += imported.map { ReaderSettings(configuration: $0).normalized.configuration }
        try await persist()
    }

    func exportSelected() throws -> Data { try ReadBookConfig.exportThemes([current]) }

    func deleteSelected() async throws {
        guard styles.count > 5 else { throw ReaderStyleError.minimumStyles }
        guard styles.indices.contains(selected) else { throw ReaderStyleError.invalidSelection }
        styles.remove(at: selected); selected = max(0, selected - 1)
        try await persist()
    }

    private func persist() async throws {
        let configs = try ReadBookConfig.exportThemes(styles)
        let sharedData = try JSONEncoder().encode(shared)
        try await database.write { db in
            for (name, data) in [("readConfig.json", configs), ("shareReadConfig.json", sharedData)] {
                try db.execute(sql: "INSERT INTO backup_files(name, data) VALUES (?, ?) ON CONFLICT(name) DO UPDATE SET data = excluded.data", arguments: [name, data])
            }
        }
        synchronizeSettings()
    }

    private func synchronizeSettings() {
        defaults.set(selected, forKey: "readStyleSelect")
        defaults.set(sharedLayout, forKey: "shareLayout")
        var settings = ReaderSettings.load(from: defaults)
        settings.configuration = current
        settings.save(to: defaults)
    }

    private static func copyColors(from visual: ReadBookConfig, into layout: ReadBookConfig) -> ReadBookConfig {
        var result = layout
        for path in [\ReadBookConfig.name, \.bgStr, \.bgStrNight, \.bgStrEInk, \.textColor, \.textColorNight,
                     \.textColorEInk, \.textAccentColor, \.textAccentColorNight, \.textAccentColorEInk] {
            result[keyPath: path] = visual[keyPath: path]
        }
        result.bgType = visual.bgType; result.bgTypeNight = visual.bgTypeNight; result.bgTypeEInk = visual.bgTypeEInk
        result.darkStatusIcon = visual.darkStatusIcon; result.darkStatusIconNight = visual.darkStatusIconNight
        result.darkStatusIconEInk = visual.darkStatusIconEInk
        return result
    }
}

enum ReaderStyleError: LocalizedError {
    case empty, invalidSelection, minimumStyles
    var errorDescription: String? {
        switch self {
        case .empty: return "阅读样式列表为空。"
        case .invalidSelection: return "所选阅读样式不存在，请重新选择。"
        case .minimumStyles: return "至少保留五套阅读样式。"
        }
    }
}
