import Foundation
import GRDB

public extension Repository where Record == SearchKeyword {
    func record(_ word: String, at timestamp: Int64) async throws {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        try await database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO search_keywords (word, usage, lastUseTime) VALUES (?, 1, ?)
                ON CONFLICT(word) DO UPDATE SET usage = usage + 1, lastUseTime = excluded.lastUseTime
                """, arguments: [word, timestamp])
        }
    }

    func history() async throws -> [SearchKeyword] {
        try await database.writer.read { db in
            try SearchKeyword.fetchAll(db, sql: "SELECT * FROM search_keywords ORDER BY lastUseTime DESC, word")
        }
    }

    func clear() async throws {
        _ = try await database.writer.write { db in try SearchKeyword.deleteAll(db) }
    }
}

public extension Repository where Record == Cache {
    func value(forKey key: String, at timestamp: Int64) async throws -> String? {
        try await database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM caches WHERE key = ? AND (deadline = 0 OR deadline > ?)", arguments: [key, timestamp])
        }
    }
}

public extension Server {
    struct WebDavConfig: Codable, Equatable, Sendable {
        public var url: String
        public var username: String
        public var password: String
        public init(url: String, username: String, password: String) {
            self.url = url; self.username = username; self.password = password
        }
    }

    func webDavConfig() throws -> WebDavConfig? {
        guard type == "WEBDAV", let config else { return nil }
        return try JSONDecoder().decode(WebDavConfig.self, from: Data(config.utf8))
    }

    mutating func setWebDavConfig(_ value: WebDavConfig) throws {
        type = "WEBDAV"
        config = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}

public extension Repository where Record == RuleSub {
    func saveImported(_ values: [RuleSub], at timestamp: Int64) async throws {
        try await database.writer.write { db in
            var used = Set(try RuleSub.fetchAll(db).map(\.id))
            var next = max(1, timestamp)
            for var value in values {
                if value.id == 0 || used.contains(value.id) {
                    while used.contains(next) { next = next == Int64.max ? 1 : next + 1 }
                    value.id = next
                }
                used.insert(value.id)
                try value.insert(db)
            }
        }
    }

    func refresh(_ subscription: RuleSub, client: any HttpClient, at timestamp: Int64) async throws -> Int {
        let content = try await SourceImporter(now: { timestamp }).fetchSubscription(subscription, client: client)
        return try await database.writer.write { db in
            let count: Int
            switch content {
            case .books(let values):
                for value in values {
                    var row = try BackupImporter.row(value.source, defaults: BookSourceRow())
                    try row.save(db)
                }
                count = values.count
            case .rss(let values):
                for var value in values { try value.save(db) }
                count = values.count
            case .replacements(let values):
                for value in values {
                    var row = try BackupImporter.row(value, defaults: ReplaceRuleRow())
                    if row.id == 0 { row.id = nil }
                    try row.save(db)
                }
                count = values.count
            }
            var saved = subscription
            saved.update = timestamp
            try saved.save(db)
            return count
        }
    }
}
