import Foundation
import GRDB

public enum DictRuleValidationError: LocalizedError, Equatable {
    case missingRequiredFields

    public var errorDescription: String? { "字典规则缺少必填字段" }
}

enum DictRuleMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v4") { db in
            if try !db.tableExists("dictRules") {
                try db.create(table: "dictRules") { t in
                    t.primaryKey("name", .text)
                    t.column("urlRule", .text).notNull().defaults(to: "")
                    t.column("showRule", .text).notNull().defaults(to: "")
                    t.column("enabled", .boolean).notNull().defaults(to: true)
                    t.column("sortNumber", .integer).notNull().defaults(to: 0)
                }
            }
            if try DictRule.fetchCount(db) == 0 {
                for rule in DictRule.builtIn { try rule.insert(db) }
            }
        }
    }
}

public struct DictRuleRepository: Sendable {
    private let database: AppDatabase
    public init(database: AppDatabase) { self.database = database }

    public func list() async throws -> [DictRule] {
        try await database.writer.read { db in
            try DictRule.fetchAll(db, sql: "SELECT * FROM dictRules ORDER BY sortNumber, name")
        }
    }

    public func save(_ rule: DictRule) async throws { try await save([rule]) }

    public func save(_ rules: [DictRule]) async throws {
        guard rules.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw DictRuleValidationError.missingRequiredFields
        }
        try await database.writer.write { db in
            for rule in rules { try rule.save(db) }
        }
    }

    public func delete(name: String) async throws {
        _ = try await database.writer.write { db in try DictRule.deleteOne(db, key: name) }
    }

    public func saveEdited(_ rule: DictRule, replacing originalName: String?) async throws {
        guard !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !rule.urlRule.isEmpty else {
            throw DictRuleValidationError.missingRequiredFields
        }
        try await database.writer.write { db in
            if rule.name != originalName, try DictRule.fetchOne(db, key: rule.name) != nil {
                throw NSError(domain: "DictRule", code: 1, userInfo: [NSLocalizedDescriptionKey: "已存在同名字典规则"])
            }
            try rule.save(db)
            if let originalName, originalName != rule.name { _ = try DictRule.deleteOne(db, key: originalName) }
        }
    }
}
