import GRDB

public typealias CookieRepository = Repository<CookieRow>

extension Repository where Record == CookieRow {
    public func mergeWebViewCookie(url: String, cookie: String) async throws -> String {
        let key = CookieStore.hostKey(url)
        return try await database.write { db in
            var row = try CookieRow.fetchOne(db, key: key) ?? CookieRow()
            row.url = key
            row.cookie = CookieStore.mergeCookies(row.cookie ?? "", cookie)
            try row.save(db)
            return row.cookie ?? ""
        }
    }

    public func get(url: String) async throws -> CookieRow? {
        try await database.writer.read { db in try CookieRow.fetchOne(db, key: url) }
    }

    public func list() async throws -> [CookieRow] {
        try await database.writer.read { db in try CookieRow.order(Column("url")).fetchAll(db) }
    }
}
