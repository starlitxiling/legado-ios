import Foundation
import GRDB

public enum BackupFileManifest {
    public static let configurationFiles = [
        "directLinkUploadRule.json", "coverRule.json", "readConfig.json", "shareReadConfig.json", "themeConfig.json"
    ]
    public static let files = [
        "bookshelf.json", "bookGroup.json", "bookMemo.json", "bookmark.json", "highlight.json", "highlightRule.json",
        "bookSource.json", "rssSources.json", "rssStar.json", "sourceSub.json", "cookies.json", "runtimeSourceCache.json",
        "replaceRule.json", "txtTocRule.json", "httpTTS.json", "keyboardAssists.json", "dictRule.json", "autoTask.json",
        "servers.json", "directLinkUploadRule.json", "coverRule.json", "readRecord.json", "searchHistory.json",
        "readConfig.json", "shareReadConfig.json", "themeConfig.json", "config.xml", "videoConfig.xml"
    ]

    static func isRuntimeCacheKey(_ key: String) -> Bool {
        ["v_", "userInfo_", "loginHeader_", "sourceVariable_", "infoMap_"].contains { key.hasPrefix($0) && key.count > $0.count }
    }

    static func importAdditional(_ name: String, data: Data, database: AppDatabase, decoder: GsonJSONDecoder, now: Int64, restoredBookURLs: Set<String> = []) async throws -> Int {
        func save<T: StorageRow>(_ type: T.Type) async throws -> Int {
            let values = try decoder.decode([T].self, from: data)
            try await database.write { db in
                for var value in values { try value.save(db) }
            }
            return values.count
        }
        switch name {
        case "bookMemo.json":
            let values = try decoder.decode([BookMemo].self, from: data).filter { restoredBookURLs.contains($0.bookUrl) }
            return try await database.writer.write { db in
                var count = 0
                for var value in values {
                    guard try BookRow.fetchOne(db, key: value.bookUrl) != nil,
                          value.updatedAt > (try BookMemo.fetchOne(db, key: value.bookUrl)?.updatedAt ?? -1) else { continue }
                    try value.save(db)
                    count += 1
                }
                return count
            }
        case "highlight.json":
            let values = try decoder.decode([BookHighlight].self, from: data)
            try await database.write { db in
                for var value in values {
                    if value.bookUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        value.bookUrl = try String.fetchOne(db, sql: "SELECT bookUrl FROM books WHERE name = ? AND author = ?", arguments: [value.bookName, value.bookAuthor]) ?? ""
                    }
                    if value.chapterUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        value.chapterUrl = try String.fetchOne(db, sql: "SELECT url FROM chapters WHERE bookUrl = ? AND \"index\" = ? AND title = ?", arguments: [value.bookUrl, value.chapterIndex, value.chapterName]) ?? ""
                    }
                    try value.save(db)
                }
            }
            return values.count
        case "highlightRule.json":
            let values = try decoder.decode([HighlightRule].self, from: data).enumerated().map { index, value in
                var value = value
                value.uuid = (UUID(uuidString: value.uuid) ?? UUID()).uuidString.lowercased()
                value.group = value.group?.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.group?.isEmpty == true { value.group = nil }
                if value.style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { value.style = BookHighlight.restoredStyle() }
                if value.timeoutMillisecond <= 0 { value.timeoutMillisecond = 3000 }
                value.id = 0
                value.order = index
                return value
            }
            guard Set(values.map(\.uuid)).count == values.count else { throw BackupArchiveError.unsupportedFormat }
            try await database.write { db in
                try HighlightRule.deleteAll(db)
                for var value in values {
                    try value.insert(db)
                }
            }
            return values.count
        case "sourceSub.json":
            let values = try decoder.decode([RuleSub].self, from: data)
            try await RuleSubRepository(database: database).saveImported(values, at: now)
            return values.count
        case "keyboardAssists.json":
            let values = try decoder.decode([KeyboardAssist].self, from: data)
            try await database.write { db in
                try KeyboardAssist.deleteAll(db)
                for var value in values { try value.save(db) }
            }
            return values.count
        case "autoTask.json": return try await save(AutoTaskRule.self)
        case "servers.json": return try await save(Server.self)
        case "searchHistory.json": return try await save(SearchKeyword.self)
        case "cookies.json":
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  rows.allSatisfy({ ($0["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && $0["cookie"] is String }) else {
                throw BackupArchiveError.unsupportedFormat
            }
            return try await save(CookieRow.self)
        case "runtimeSourceCache.json":
            guard case let .array(elements) = try GsonValue.parse(data) else { throw BackupArchiveError.unsupportedFormat }
            for element in elements {
                guard case .string(let key)? = element["key"], isRuntimeCacheKey(key),
                      let value = element["value"], let deadline = element["deadline"] else { throw BackupArchiveError.unsupportedFormat }
                switch value { case .null, .string: break; default: throw BackupArchiveError.unsupportedFormat }
                guard case .number(let raw) = deadline, let number = Int64(raw), number >= 0 else {
                    throw BackupArchiveError.unsupportedFormat
                }
            }
            let values = try decoder.decode([Cache].self, from: data).filter { $0.deadline == 0 || $0.deadline > now }
            try await CacheRepository(database: database).upsert(values)
            return values.count
        default:
            guard configurationFiles.contains(name) else { throw BackupArchiveError.unsupportedFormat }
            _ = try GsonValue.parse(data)
            try await database.write { db in
                try db.execute(sql: "INSERT OR REPLACE INTO backup_files (name, data) VALUES (?, ?)", arguments: [name, data])
            }
            return 1
        }
    }
}
