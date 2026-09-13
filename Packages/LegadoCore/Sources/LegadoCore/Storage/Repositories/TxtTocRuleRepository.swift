import GRDB

public struct TxtTocRuleRepository: Sendable {
    private let database: AppDatabase
    public init(database: AppDatabase) { self.database = database }

    public func list(enabledOnly: Bool = false) async throws -> [TxtTocRule] {
        try await database.writer.read { db in
            try TxtTocRule.fetchAll(db, sql: "SELECT * FROM txtTocRules \(enabledOnly ? "WHERE enable = 1" : "") ORDER BY serialNumber, id")
        }
    }

    public func save(_ rule: TxtTocRule) async throws {
        try rule.validate()
        try await database.writer.write { db in try rule.save(db) }
    }
}
