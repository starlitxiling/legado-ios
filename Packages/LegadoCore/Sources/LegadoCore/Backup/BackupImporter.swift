import Foundation
import GRDB

public struct BackupImportReport {
    public internal(set) var preferences: [String: AndroidPreferenceValue]?
    public internal(set) var videoPreferences: [String: AndroidPreferenceValue]?
    public internal(set) var importedFiles: [String] = []
    public internal(set) var importedCounts: [String: Int] = [:]
    public internal(set) var skippedFiles: [String] = []
    public internal(set) var failures: [String: String] = [:]
    public internal(set) var discardedFields: [String: [String]] = [:]
}

public struct BackupImporter {
    private let resourceDirectory: URL?
    private let database: AppDatabase
    private let localDeviceID: String
    private let now: () -> Int64

    /// localDeviceID 由应用持久化身份提供，避免把旧备份的空设备 ID 当成远端设备。
    public init(database: AppDatabase, localDeviceID: String, now: @escaping () -> Int64 = GsonDecoding.currentTimeMillis) {
        self.init(database: database, localDeviceID: localDeviceID, now: now, resourceDirectory: nil)
    }

    public init(database: AppDatabase, localDeviceID: String, now: @escaping () -> Int64 = GsonDecoding.currentTimeMillis, resourceDirectory: URL?) {
        self.resourceDirectory = resourceDirectory
        self.database = database
        self.localDeviceID = localDeviceID
        self.now = now
    }

    public func importArchive(_ data: Data) async throws -> BackupImportReport {
        try await importArchive(data, selection: .init())
    }

    public func importArchive(_ archive: BackupArchive) async throws -> BackupImportReport {
        try await importArchive(archive, selection: .init())
    }

    public func importArchive(_ data: Data, selection: BackupSelection) async throws -> BackupImportReport {
        try await importArchive(BackupArchive(data: data), selection: selection)
    }

    public func importArchive(_ archive: BackupArchive, selection: BackupSelection) async throws -> BackupImportReport {
        guard !localDeviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.missingDeviceID
        }
        var order = ["bookshelf.json", "bookMemo.json", "bookmark.json", "highlight.json", "highlightRule.json", "bookGroup.json", "bookSource.json", "rssSources.json", "rssStar.json", "replaceRule.json", "searchHistory.json", "sourceSub.json", "txtTocRule.json", "httpTTS.json", "dictRule.json", "keyboardAssists.json", "readRecord.json", "servers.json", "config.xml", "videoConfig.xml"]
        order += BackupFileManifest.files.filter { !order.contains($0) }
        var report = BackupImportReport()
        report.skippedFiles = archive.files.keys.filter { !order.contains($0) }.sorted()
        if let resourceDirectory {
            let restored = try BackupResources.restore(archive, root: resourceDirectory, selection: selection)
            report.importedFiles.append(contentsOf: restored)
            report.skippedFiles.removeAll { restored.contains($0) }
        }
        let available = Set(report.importedFiles)
        let timestamp = now()

        let decoder = GsonJSONDecoder(now: { timestamp })
        var restoredBookURLs = Set<String>()
        for name in order {
            try Task.checkCancellation()
            guard let data = archive.files[name] else { continue }
            if selection.ignoresFile(name) { report.skippedFiles.append(name); continue }
            do {
                let data = try BackupResources.rewrite(data, name: name, root: resourceDirectory, available: available, exporting: false, selection: selection)
                let count: Int
                switch name {
                case "bookMemo.json", "highlight.json", "highlightRule.json", "sourceSub.json",
                     "keyboardAssists.json", "autoTask.json", "servers.json", "searchHistory.json",
                     "cookies.json", "runtimeSourceCache.json", "directLinkUploadRule.json",
                     "coverRule.json", "readConfig.json", "shareReadConfig.json", "themeConfig.json":
                    count = try await BackupFileManifest.importAdditional(name, data: data, database: database, decoder: decoder, now: timestamp, restoredBookURLs: restoredBookURLs)
                case "config.xml":
                    var values = try AndroidPreferencesXML.decode(data)
                    if let root = resourceDirectory {
                        for key in ["readRecordCover", "readRecordCoverDark", "coverFont", "backgroundImage", "backgroundImageNight"] {
                            guard case let .string(path)? = values[key] else { continue }
                            if key == "coverFont" {
                                guard case .file = CoverFontReference(path) else { continue }
                            }
                            let relative = key == "coverFont" ? "font/coverFont.ttf" : BackupResources.relativePath(path)
                            if let relative {
                                let target = root.appendingPathComponent(relative)
                                values[key] = .string(FileManager.default.fileExists(atPath: target.path) ? target.path : "")
                            }
                        }
                    }

                    report.preferences = values.filter { selection.allowsPreference($0.key) }
                    count = report.preferences?.count ?? 0
                case "videoConfig.xml":
                    let values = try AndroidPreferencesXML.decode(data)
                    report.videoPreferences = values
                    count = values.count
                case "txtTocRule.json":
                    let values = try decoder.decode([TxtTocRule].self, from: data)
                    try await database.write { db in for value in values { try value.save(db) } }
                    count = values.count
                case "dictRule.json":
                    let values = try decoder.decode([DictRule].self, from: data)
                    try await database.write { db in for value in values { try value.save(db) } }
                    count = values.count
                case "bookshelf.json":
                    let values = try decoder.decode([Book].self, from: data)
                    let rows = try values.map { Self.normalizeBook(try Self.row($0, defaults: BookRow())) }
                        .filter { selection.values["localBook"] != true || ($0.type & 256 == 0 && $0.origin != "loc_book" && !$0.origin.hasPrefix("webDav::")) }
                    try await BookshelfRepository(database: database).restoreBackupBooks(rows)
                    restoredBookURLs.formUnion(rows.map(\.bookUrl))
                    count = rows.count
                case "bookmark.json":
                    let rows = try decoder.decode([Bookmark].self, from: data).map { try Self.row($0, defaults: BookmarkRow()) }
                    try await BookmarkRepository(database: database).upsert(rows)
                    count = rows.count
                case "bookGroup.json":
                    let rows = try decoder.decode([BookGroup].self, from: data).map { try Self.row($0, defaults: BookGroupRow()) }
                    try await BookGroupRepository(database: database).upsert(rows)
                    count = rows.count
                case "bookSource.json":
                    guard case let .sources(values) = SourceImporter(now: { timestamp }).parseBookSources(String(decoding: data, as: UTF8.self)) else {
                        throw ImportError.invalidSources
                    }
                    let rows = try values.map { try Self.row($0.source, defaults: BookSourceRow()) }
                    try await BookSourceRepository(database: database).upsert(rows)
                    count = rows.count
                case "rssSources.json":
                    let values = try decoder.decode([RssSource].self, from: data)
                    try await RssRepository(database: database).saveSources(values)
                    count = values.count
                case "rssStar.json":
                    let values = try decoder.decode([RssStar].self, from: data)
                    try await RssRepository(database: database).saveStars(values)
                    count = values.count
                case "replaceRule.json":
                    // Restore 直接解码实体，不能套用交互导入对正则的过滤。
                    let values = try decoder.decode([ReplaceRule].self, from: data)
                    let rows = try values.map { try Self.row($0, defaults: ReplaceRuleRow()) }
                    count = try await ReplaceRuleRepository(database: database).restoreBackupRules(rows)
                    if values.contains(where: { $0.previewText != nil }) {
                        report.discardedFields[name] = ["previewText"]
                    }
                case "httpTTS.json":
                    let values = try decoder.decode([HttpTTS].self, from: data)
                    try await HttpTTSRepository(database: database).upsert(values)
                    count = values.count
                default:
                    let rows = try decoder.decode([ReadRecord].self, from: data).map { value -> ReadRecordRow in
                        var row = try Self.row(value, defaults: ReadRecordRow())
                        if row.deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { row.deviceId = localDeviceID }
                        return row
                    }
                    try await ReadProgressRepository(database: database).restoreBackupReading(rows, localDeviceID: localDeviceID)
                    count = rows.count
                }
                report.importedFiles.append(name)
                report.importedCounts[name] = count
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                report.failures[name] = String(describing: error)
            }
        }
        return report
    }

    private enum ImportError: Error { case missingDeviceID, invalidSources }

    static func normalizeBook(_ book: BookRow) -> BookRow {
        var result = book
        if result.type < 4 {
            switch result.type {
            case 1: result.type = 32
            case 2: result.type = 64
            case 3: result.type = 128
            default: result.type = 8
            }
            if result.origin == "loc_book" || result.origin.hasPrefix("webDav::") { result.type |= 256 }
        }
        if result.persistedCoverUrl?.isEmpty ?? true, let path = result.customCoverUrl,
           path.hasPrefix("/"), path.range(of: #"/covers/[0-9a-fA-F]{32}\.cover$"#, options: .regularExpression) != nil {
            result.persistedCoverUrl = path
            result.customCoverUrl = nil
        }
        return result
    }

    /// 复用实体的 Gson 解码；Row 的 JSON 复合列与 Room TypeConverter 一样保存 JSON 文本。
    static func row<Value: Encodable, Row: StorageRow>(_ value: Value, defaults: Row) throws -> Row {
        let encoder = JSONEncoder()
        var fields = try JSONSerialization.jsonObject(with: encoder.encode(defaults)) as! [String: Any]
        let incoming = try JSONSerialization.jsonObject(with: encoder.encode(value)) as! [String: Any]
        for (key, value) in incoming {
            let column = Row.self == ReplaceRuleRow.self && key == "order" ? "sortOrder" : key
            if value is [String: Any] || value is [Any] {
                let text = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
                fields[column] = String(decoding: text, as: UTF8.self)
            } else {
                fields[column] = value
            }
        }
        return try JSONDecoder().decode(Row.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    static func mergeReading(current: ReadRecordRow?, incoming: ReadRecordRow, localDeviceID: String) -> ReadRecordRow {
        guard let current, current.deviceId == incoming.deviceId, current.bookName == incoming.bookName,
              current.author == incoming.author else { return incoming }
        let latest = incoming.lastRead >= current.lastRead ? incoming : current
        let previous = incoming.lastRead >= current.lastRead ? current : incoming
        let chapter = latest.lastChapterIndex >= 0 || !(latest.lastChapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? latest : previous
        var result = incoming
        result.readTime = incoming.deviceId == localDeviceID ? max(current.readTime, incoming.readTime) : incoming.readTime
        result.lastRead = max(current.lastRead, incoming.lastRead)
        result.lastChapterTitle = chapter.lastChapterTitle
        result.lastChapterIndex = chapter.lastChapterIndex
        result.lastChapterPos = chapter.lastChapterPos
        result.coverUrl = latest.coverUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? latest.coverUrl : previous.coverUrl
        result.resolvedAuthor = current.resolvedAuthor ?? incoming.resolvedAuthor
        return result
    }
}

private extension Repository where Record == BookRow {
    func restoreBackupBooks(_ rows: [BookRow]) async throws {
        try await database.writer.write { db in
            for var row in rows {
                do {
                    try row.save(db)
                } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
                    try row.insert(db, onConflict: .replace)
                }
            }
        }
    }
}

private extension Repository where Record == ReadRecordRow {
    func restoreBackupReading(_ rows: [ReadRecordRow], localDeviceID: String) async throws {
        try await database.writer.write { db in
            for row in rows {
                let current = try ReadRecordRow.fetchOne(db, key: ["deviceId": row.deviceId, "bookName": row.bookName, "author": row.author])
                var merged = BackupImporter.mergeReading(current: current, incoming: row, localDeviceID: localDeviceID)
                try merged.save(db)
            }
        }
    }
}

private extension Repository where Record == ReplaceRuleRow {
    func restoreBackupRules(_ rows: [ReplaceRuleRow]) async throws -> Int {
        try await database.writer.write { db in
            var importedIDs = Set<Int64>()
            for var row in rows {
                // Room 将自增 Long 主键的零值绑定为 NULL；非零冲突使用 REPLACE。
                if row.id == 0 { row.id = nil }
                try row.insert(db, onConflict: .replace)
                if let id = row.id { importedIDs.insert(id) }
            }
            return importedIDs.count
        }
    }
}
