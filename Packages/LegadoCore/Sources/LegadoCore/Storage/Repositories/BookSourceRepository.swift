import GRDB

public typealias BookSourceRepository = Repository<BookSourceRow>

extension Repository where Record == BookSourceRow {
    public func get(bookSourceUrl: String) async throws -> BookSourceRow? {
        try await database.writer.read { db in try BookSourceRow.fetchOne(db, key: bookSourceUrl) }
    }

    public func list(enabled: Bool? = nil) async throws -> [BookSourceRow] {
        try await database.writer.read { db in
            if let enabled {
                return try BookSourceRow.fetchAll(db, sql: "SELECT * FROM book_sources WHERE enabled = ? ORDER BY customOrder, bookSourceUrl", arguments: [enabled])
            }
            return try BookSourceRow.fetchAll(db, sql: "SELECT * FROM book_sources ORDER BY customOrder, bookSourceUrl")
        }
    }
}
