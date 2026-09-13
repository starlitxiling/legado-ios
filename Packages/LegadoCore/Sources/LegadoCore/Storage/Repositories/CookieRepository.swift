import GRDB

public typealias CookieRepository = Repository<CookieRow>

extension Repository where Record == CookieRow {
    public func get(url: String) async throws -> CookieRow? {
        try await database.writer.read { db in try CookieRow.fetchOne(db, key: url) }
    }

    public func list() async throws -> [CookieRow] {
        try await database.writer.read { db in try CookieRow.order(Column("url")).fetchAll(db) }
    }
}
