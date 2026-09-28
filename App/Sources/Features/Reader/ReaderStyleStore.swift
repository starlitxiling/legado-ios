import Foundation
import Observation
import CoreText
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
    private let resourceDirectory: URL
    private let fontDirectory: URL
    private let log: AppLogStore
    private var pendingOriginals: [String: Data] = [:]

    init(database: AppDatabase, defaults: UserDefaults = .standard,
         resourceDirectory: URL = URL.applicationSupportDirectory.appendingPathComponent("Legado/bg"),
         fontDirectory: URL = URL.applicationSupportDirectory.appendingPathComponent("fonts"),
         log: AppLogStore = .shared) {
        self.database = database; self.defaults = defaults
        self.resourceDirectory = resourceDirectory; self.fontDirectory = fontDirectory; self.log = log
    }

    var current: ReadBookConfig {
        guard styles.indices.contains(selected) else { return ReadBookConfig() }
        return sharedLayout ? Self.copyColors(from: styles[selected], into: shared) : styles[selected]
    }

    func load() async throws {
        let saved = try await database.backupConfiguration(named: "readConfig.json")
        let presets = try ReadBookConfig.bundledStyles()
        var loaded = presets
        var fallback = false
        if let saved {
            do {
                loaded = try ReadBookConfig.importThemes(saved) { index, error in
                    fallback = true
                    self.log.append("readConfig.json[\(index)] fallback: \(String(reflecting: error))")
                }
                guard !loaded.isEmpty else { throw ReaderStyleError.empty }
            } catch {
                log.append("readConfig.json fallback: \(String(reflecting: error))")
                loaded = presets
                fallback = true
            }
            if fallback { pendingOriginals["readConfig.json"] = saved }
        }
        selected = min(max(0, defaults.integer(forKey: "readStyleSelect")), loaded.count - 1)
        if saved == nil {
            var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded[selected])) as! [String: Any]
            ReaderSettings.mergePreferences(into: &fields, defaults: defaults)
            loaded[selected] = try JSONDecoder().decode(ReadBookConfig.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        styles = loaded.map { ReaderSettings(configuration: $0).normalized.configuration }
        let sharedData = try await database.backupConfiguration(named: "shareReadConfig.json")
        shared = styles[min(5, styles.count - 1)]
        if let sharedData {
            do { shared = try JSONDecoder().decode(ReadBookConfig.self, from: sharedData) }
            catch {
                log.append("shareReadConfig.json fallback: \(String(reflecting: error))")
                shared = presets[min(5, presets.count - 1)]
                pendingOriginals["shareReadConfig.json"] = sharedData
                fallback = true
            }
        }
        sharedLayout = defaults.bool(forKey: "shareLayout")
        try await preserveOriginals()
        if !fallback { synchronizeSettings() }
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
        try await preserveOriginals()
        let imported: [ReadBookConfig]
        if data.starts(with: [0x50, 0x4b]) {
            let archive = try ReaderStyleArchive.decode(data)
            var config = archive.configuration
            var installed: [String: String] = [:]
            for (type, path) in [(config.bgType, \ReadBookConfig.bgStr), (config.bgTypeNight, \.bgStrNight), (config.bgTypeEInk, \.bgStrEInk)] where type == 2 {
                let name = config[keyPath: path]
                if installed[name] == nil {
                    let target = UUID().uuidString + "-" + name
                    try FileManager.default.createDirectory(at: resourceDirectory, withIntermediateDirectories: true)
                    try archive.files[name]!.write(to: resourceDirectory.appendingPathComponent(target), options: .atomic)
                    installed[name] = target
                }
                config[keyPath: path] = installed[name]!
            }
            for path in [\ReadBookConfig.textFont, \.titleFont] where !config[keyPath: path].isEmpty {
                let name = config[keyPath: path]
                let target = fontDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
                try FileManager.default.createDirectory(at: fontDirectory, withIntermediateDirectories: true)
                try archive.files[name]!.write(to: target, options: .atomic)
                guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(target as CFURL) as? [CTFontDescriptor],
                      let first = descriptors.first, let fontName = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String else {
                    try FileManager.default.removeItem(at: target)
                    throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: name])
                }
                CTFontManagerRegisterFontsForURL(target as CFURL, .process, nil)
                config[keyPath: path] = fontName
            }
            imported = [config]
        } else {
            var fallback = false
            imported = try ReadBookConfig.importThemes(data) { index, error in
                fallback = true
                self.log.append("Imported style[\(index)] fallback: \(String(reflecting: error))")
            }
            if fallback {
                pendingOriginals["readConfig.json"] = data
                try await preserveOriginals()
            }
        }
        guard !imported.isEmpty else { throw ReaderStyleError.empty }
        selected = styles.count
        styles += imported.map { ReaderSettings(configuration: $0).normalized.configuration }
        try await persist()
    }

    func importStyles(from address: String, client: any ResponseLimitedHttpClient) async throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { throw URLError(.badURL) }
        let response = try await client.send(HttpRequest(url: url), maximumResponseBytes: 16 * 1024 * 1024)
        guard (200..<300).contains(response.status) else { throw WebBookError.httpStatus(response.status, url.absoluteString) }
        try Task.checkCancellation()
        try await importStyles(response.body)
    }

    func exportSelected() throws -> Data {
        try ReaderStyleArchive.encode(current, background: { name in
            let url = resourceDirectory.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent)
            return try Data(contentsOf: url)
        }, font: { name in
            guard FileManager.default.fileExists(atPath: fontDirectory.path) else { return nil }
            for url in try FileManager.default.contentsOfDirectory(at: fontDirectory, includingPropertiesForKeys: nil) {
                let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
                if descriptors.contains(where: { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == name }) {
                    return (url.lastPathComponent, try Data(contentsOf: url))
                }
            }
            return nil
        })
    }

    func createStyle() async throws {
        var style = ReadBookConfig()
        style.name = "新样式"
        styles.append(style)
        selected = styles.count - 1
        try await persist()
    }

    func restorePresetLayout() async throws {
        let presets = try ReadBookConfig.bundledStyles()
        let preset = presets.indices.contains(selected) ? presets[selected] : presets[0]
        try await update(Self.copyColors(from: current, into: preset))
    }

    func deleteSelected() async throws {
        guard styles.count > 5 else { throw ReaderStyleError.minimumStyles }
        guard styles.indices.contains(selected) else { throw ReaderStyleError.invalidSelection }
        styles.remove(at: selected); selected = max(0, selected - 1)
        try await persist()
    }

    private func preserveOriginals() async throws {
        for (name, data) in pendingOriginals {
            let stem = (name as NSString).deletingPathExtension
            let backupName = stem + ".broken-" + String(Int64(Date().timeIntervalSince1970 * 1000)) + "-" + UUID().uuidString + ".json"
            try await database.write { db in
                try db.execute(sql: "INSERT INTO backup_files(name, data) VALUES (?, ?)", arguments: [backupName, data])
            }
            pendingOriginals.removeValue(forKey: name)
        }
    }

    private func persist() async throws {
        try await preserveOriginals()
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
        result.bgAlpha = visual.bgAlpha
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
