import Foundation
import GRDB

public struct BackupImportReport {
    public internal(set) var importedFiles: [String] = []
    public internal(set) var importedCounts: [String: Int] = [:]
    public internal(set) var skippedFiles: [String] = []
    public internal(set) var failures: [String: String] = [:]
    public internal(set) var discardedFields: [String: [String]] = [:]
}

public struct BackupImporter {
    private let database: AppDatabase
    private let localDeviceID: String
    private let now: () -> Int64

    /// localDeviceID 由应用持久化身份提供，避免把旧备份的空设备 ID 当成远端设备。
    public init(database: AppDatabase, localDeviceID: String, now: @escaping () -> Int64 = GsonDecoding.currentTimeMillis) {
        self.database = database
        self.localDeviceID = localDeviceID
        self.now = now
    }

    public func importArchive(_ data: Data) async throws -> BackupImportReport {
        try await importArchive(BackupArchive(data: data))
    }

    public func importArchive(_ archive: BackupArchive) async throws -> BackupImportReport {
        guard !localDeviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.missingDeviceID
        }
        let order = ["bookshelf.json", "bookmark.json", "bookGroup.json", "bookSource.json", "replaceRule.json", "readRecord.json"]
        var report = BackupImportReport()
        report.skippedFiles = archive.files.keys.filter { !order.contains($0) }.sorted()
        let timestamp = now()
        let decoder = GsonJSONDecoder(now: { timestamp })
        for name in order {
            try Task.checkCancellation()
            guard let data = archive.files[name] else { continue }
            do {
                let count: Int
                switch name {
                case "bookshelf.json":
                    let values = try decoder.decode([Book].self, from: data)
                    let rows = try values.map { Self.normalizeBook(try Self.row($0, defaults: BookRow())) }
                    try await BookshelfRepository(database: database).restoreBackupBooks(rows)
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
                case "replaceRule.json":
                    // Restore 直接解码实体，不能套用交互导入对正则的过滤。
                    let values = try decoder.decode([ReplaceRule].self, from: data)
                    let rows = try values.map { try Self.row($0, defaults: ReplaceRuleRow()) }
                    count = try await ReplaceRuleRepository(database: database).restoreBackupRules(rows)
                    if values.contains(where: { $0.previewText != nil }) {
                        report.discardedFields[name] = ["previewText"]
                    }
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
    private static func row<Value: Encodable, Row: StorageRow>(_ value: Value, defaults: Row) throws -> Row {
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
