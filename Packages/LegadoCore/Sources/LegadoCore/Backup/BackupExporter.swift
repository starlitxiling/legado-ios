import Foundation
import GRDB

public struct BackupExporter {
    private let resourceDirectory: URL?
    private let database: AppDatabase
    private let now: () -> Date
    private let timeZone: TimeZone

    public init(database: AppDatabase, now: @escaping () -> Date = Date.init, timeZone: TimeZone = .current) {
        self.init(database: database, now: now, timeZone: timeZone, resourceDirectory: nil)
    }

    public init(database: AppDatabase, now: @escaping () -> Date = Date.init, timeZone: TimeZone = .current, resourceDirectory: URL?) {
        self.resourceDirectory = resourceDirectory
        self.database = database; self.now = now; self.timeZone = timeZone
    }

    public func fileName(deviceName: String = "") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let suffix = deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "-" + deviceName
        return Self.normalizeFileName("backup" + formatter.string(from: now()) + suffix + ".zip")
    }

    static func normalizeFileName(_ name: String) -> String {
        String(name.map { "\\/:*?\"<>|".contains($0) ? "_" : $0 })
    }

    public static func shouldBackup(enabled: Bool, now: Int64, lastBackup: Int64, intervalDays: Int) -> Bool {
        enabled && Double(now) - Double(lastBackup) >= Double(max(1, intervalDays)) * 86400000
    }

    public func export(preferences: [String: AndroidPreferenceValue] = [:], videoPreferences: [String: AndroidPreferenceValue] = [:],
                       includeSourceState: Bool = false, currentConfigurationFiles: [String: Data] = [:]) async throws -> Data {
        try await export(preferences: preferences, videoPreferences: videoPreferences, includeSourceState: includeSourceState,
                         currentConfigurationFiles: currentConfigurationFiles, selection: nil)
    }

    public func export(preferences: [String: AndroidPreferenceValue] = [:], videoPreferences: [String: AndroidPreferenceValue] = [:],
                       includeSourceState: Bool = false, currentConfigurationFiles: [String: Data] = [:],
                       selection: BackupSelection?) async throws -> Data {
        let selection = selection ?? BackupSelection(values: includeSourceState ? ["backupCookies": false, "backupSourceVariables": false] : [:])
        var files: [(String, Data)] = []
        func append<T: Encodable>(_ name: String, _ values: [T], composites: Set<String> = []) throws {
            guard selection.includesFile(name) else { return }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            var rows = try JSONSerialization.jsonObject(with: encoder.encode(values)) as! [[String: Any]]
            for index in rows.indices {
                for key in composites {
                    if let value = rows[index][key] as? String {
                        rows[index][key] = try JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])
                    }
                }
                if name == "replaceRule.json" { rows[index]["order"] = rows[index].removeValue(forKey: "sortOrder") }
            }
            files.append((name, try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])))
        }
        try append("bookshelf.json", await BookshelfRepository(database: database).all(), composites: ["readConfig"])
        try append("bookGroup.json", await BookGroupRepository(database: database).all())
        try append("bookmark.json", await BookmarkRepository(database: database).all())
        try append("bookSource.json", await BookSourceRepository(database: database).all(), composites: ["ruleExplore", "ruleSearch", "ruleBookInfo", "ruleToc", "ruleContent", "ruleReview"])
        try append("replaceRule.json", await ReplaceRuleRepository(database: database).all())
        try append("txtTocRule.json", await TxtTocRuleRepository(database: database).list())
        try append("httpTTS.json", await HttpTTSRepository(database: database).list())
        try append("dictRule.json", await DictRuleRepository(database: database).list())
        try append("readRecord.json", await ReadProgressRepository(database: database).all())
        try append("rssSources.json", await RssRepository(database: database).sources())
        try append("rssStar.json", await RssRepository(database: database).stars())
        try append("highlight.json", await Repository<BookHighlight>(database: database).all())
        try append("bookMemo.json", await optionalRows(BookMemo.self))
        try append("highlightRule.json", await optionalRows(HighlightRule.self))
        try append("sourceSub.json", await optionalRows(RuleSub.self))
        try append("keyboardAssists.json", await optionalRows(KeyboardAssist.self))
        try append("autoTask.json", await optionalRows(AutoTaskRule.self))
        try append("servers.json", await optionalRows(Server.self))
        try append("searchHistory.json", await optionalRows(SearchKeyword.self))
        // Android 默认不选择 Cookie 和运行时变量；显式开启时采用 Restore 支持的明文 JSON。
        if selection.includes("backupCookies") || selection.includes("backupSourceVariables") {
            try append("cookies.json", await CookieRepository(database: database).all())
            let timestamp = Int64(now().timeIntervalSince1970 * 1000)
            let caches = try await CacheRepository(database: database).all().filter {
                BackupFileManifest.isRuntimeCacheKey($0.key) && ($0.deadline == 0 || $0.deadline > timestamp)
            }
            try append("runtimeSourceCache.json", caches)
        }
        for name in BackupFileManifest.configurationFiles {
            if ["readConfig.json", "shareReadConfig.json", "themeConfig.json"].contains(name) {
                let fallback = name == "shareReadConfig.json" ? "{}" : name == "readConfig.json" ? "[{}]" : "[]"
                let retained = try await database.backupConfiguration(named: name)
                files.append((name, currentConfigurationFiles[name] ?? retained ?? Data(fallback.utf8)))
                continue
            }
            let data = try await database.writer.read { db in
                try Data.fetchOne(db, sql: "SELECT data FROM backup_files WHERE name = ?", arguments: [name])
            }
            if let data { files.append((name, data)) }
        }
        files.append(("config.xml", AndroidPreferencesXML.encode(preferences.filter { selection.allowsPreference($0.key) })))
        files.append(("videoConfig.xml", AndroidPreferencesXML.encode(videoPreferences)))
        if let resourceDirectory {
            try BackupResources.collect(root: resourceDirectory, files: &files, preferences: preferences, selection: selection)
        }
        let available = Set(files.map(\.0))
        files = try files.map { (name, data) in
            (name, try BackupResources.rewrite(data, name: name, root: resourceDirectory, available: available, exporting: true, selection: selection))
        }
        let order = BackupFileManifest.files

        return try Self.zip(files.filter {
            selection.includesFile($0.0) && (!BackupFileManifest.configurationFiles.contains($0.0) || !selection.ignoresFile($0.0))
        }.sorted { (order.firstIndex(of: $0.0) ?? order.count, $0.0) < (order.firstIndex(of: $1.0) ?? order.count, $1.0) })
    }

    private func optionalRows<T: StorageRow>(_ type: T.Type) async throws -> [T] {
        try await database.writer.read { db in
            guard try db.tableExists(T.databaseTableName) else { return [] }
            return try T.fetchAll(db)
        }
    }

    private static func zip(_ files: [(String, Data)]) throws -> Data {
        var data = Data(), central = Data()
        func number(_ value: Int, _ bytes: Int, into output: inout Data) {
            for shift in 0..<bytes { output.append(UInt8(truncatingIfNeeded: value >> (shift * 8))) }
        }
        for (name, payload) in files {
            try Task.checkCancellation()
            let filename = Data(name.utf8), offset = data.count, crc = Int(BackupArchive.crc32(payload))
            guard payload.count < Int(UInt32.max), offset < Int(UInt32.max) else { throw BackupArchiveError.sizeLimit }
            number(0x04034b50, 4, into: &data)
            for value in [20, 0x800, 0, 0, 33] { number(value, 2, into: &data) }
            for value in [crc, payload.count, payload.count] { number(value, 4, into: &data) }
            number(filename.count, 2, into: &data); number(0, 2, into: &data)
            data.append(filename); data.append(payload)
            number(0x02014b50, 4, into: &central)
            for value in [20, 20, 0x800, 0, 0, 33] { number(value, 2, into: &central) }
            for value in [crc, payload.count, payload.count] { number(value, 4, into: &central) }
            for value in [filename.count, 0, 0, 0, 0] { number(value, 2, into: &central) }
            number(0, 4, into: &central); number(offset, 4, into: &central); central.append(filename)
        }
        let offset = data.count
        guard offset < Int(UInt32.max) else { throw BackupArchiveError.sizeLimit }
        data.append(central); number(0x06054b50, 4, into: &data)
        for value in [0, 0, files.count, files.count] { number(value, 2, into: &data) }
        number(central.count, 4, into: &data); number(offset, 4, into: &data); number(0, 2, into: &data)
        return data
    }
}
