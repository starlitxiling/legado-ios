import GRDB

public typealias SearchCacheRepository = Repository<SearchBookRow>

extension Repository where Record == SearchBookRow {
    public func get(bookUrl: String) async throws -> SearchBookRow? {
        try await database.writer.read { db in try SearchBookRow.fetchOne(db, key: bookUrl) }
    }

    public func list(name: String, author: String) async throws -> [SearchBookRow] {
        try await database.writer.read { db in
            try SearchBookRow.fetchAll(db, sql: "SELECT * FROM searchBooks WHERE name = ? AND author = ? ORDER BY originOrder, bookUrl", arguments: [name, author])
        }
    }

    public func clear(name: String, author: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM searchBooks WHERE name = ? AND author = ?", arguments: [name, author])
        }
    }

    public func clearExpired(before time: Int64) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM searchBooks WHERE time < ?", arguments: [time])
        }
    }
}
