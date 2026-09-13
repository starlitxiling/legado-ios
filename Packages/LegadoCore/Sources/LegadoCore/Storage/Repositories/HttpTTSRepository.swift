import GRDB

public struct HttpTTSRepository: Sendable {
    private let database: AppDatabase
    public init(database: AppDatabase) { self.database = database }
    public func list() async throws -> [HttpTTS] {
        try await database.writer.read { db in try HttpTTS.fetchAll(db, sql: "SELECT * FROM httpTTS ORDER BY id") }
    }
    public func upsert(_ sources: [HttpTTS]) async throws {
        try await database.write { db in for source in sources { try source.save(db) } }
    }
}

enum HttpTTSMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3") { db in
            try db.create(table: "httpTTS") { t in
                t.primaryKey("id", .integer)
                t.column("name", .text).notNull(); t.column("url", .text).notNull()
                t.column("contentType", .text); t.column("pauseDuration", .integer).notNull().defaults(to: 0)
                t.column("concurrentRate", .text); t.column("loginUrl", .text); t.column("loginUi", .text)
                t.column("header", .text); t.column("jsLib", .text); t.column("enabledCookieJar", .boolean)
                t.column("loginCheckJs", .text); t.column("lastUpdateTime", .integer).notNull()
            }
        }
    }
}
