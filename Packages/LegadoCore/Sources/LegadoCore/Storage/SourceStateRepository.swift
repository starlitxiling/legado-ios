import Foundation
import GRDB

public struct SourceStateRepository: Sendable {
    private let database: AppDatabase
    public init(database: AppDatabase) { self.database = database }

    func value(source: String, key: String) throws -> String? {
        try database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM source_state WHERE source = ? AND key = ?", arguments: [source, key])
        }
    }

    func setValue(source: String, key: String, value: String?) throws {
        try database.writer.write { db in
            if let value {
                try db.execute(sql: "INSERT INTO source_state(source, key, value) VALUES (?, ?, ?) ON CONFLICT(source, key) DO UPDATE SET value = excluded.value", arguments: [source, key, value])
            } else {
                try db.execute(sql: "DELETE FROM source_state WHERE source = ? AND key = ?", arguments: [source, key])
            }
        }
    }

    public func load(source: String) async throws -> [String: String] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM source_state WHERE source = ?", arguments: [source])
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["key"] as String, $0["value"] as String) })
        }
    }

    public func save(source: String, values: [String: String]) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM source_state WHERE source = ?", arguments: [source])
            for (key, value) in values {
                try db.execute(sql: "INSERT INTO source_state(source, key, value) VALUES (?, ?, ?)", arguments: [source, key, value])
            }
        }
    }

    func merge(source: String, original: [String: String], updated: [String: String]) async throws {
        try await database.write { db in
            for key in Set(original.keys).union(updated.keys) where original[key] != updated[key] {
                if let value = updated[key] {
                    try db.execute(sql: "INSERT INTO source_state(source, key, value) VALUES (?, ?, ?) ON CONFLICT(source, key) DO UPDATE SET value = excluded.value", arguments: [source, key, value])
                } else {
                    try db.execute(sql: "DELETE FROM source_state WHERE source = ? AND key = ?", arguments: [source, key])
                }
            }
        }
    }

    func clearCookies(domain: String) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM cookies WHERE url = ?", arguments: [domain])
            let rows = try Row.fetchAll(db, sql: "SELECT source, value FROM source_state WHERE key = 'loginHeader'")
            for row in rows {
                let source: String = row["source"]
                guard CookieStore.hostKey(source) == domain else { continue }
                let text: String = row["value"]
                guard var headers = try? JSONDecoder().decode([String: String].self, from: Data(text.utf8)) else { continue }
                for key in headers.keys.filter({ $0.lowercased() == "cookie" }) { headers.removeValue(forKey: key) }
                let value = String(decoding: try JSONEncoder().encode(headers), as: UTF8.self)
                try db.execute(sql: "UPDATE source_state SET value = ? WHERE source = ? AND key = 'loginHeader'", arguments: [value, source])
            }
        }
    }
}

enum SourceLoginMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2-source-login") { db in
            try db.create(table: "source_state") { t in
                t.column("source", .text).notNull()
                t.column("key", .text).notNull()
                t.column("value", .text).notNull()
                t.primaryKey(["source", "key"])
            }
        }
    }
}
