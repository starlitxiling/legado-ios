import GRDB

public typealias ReplaceRuleRepository = Repository<ReplaceRuleRow>

// Kotlin SearchBookDao.GROUP_TRIM_CHARACTERS，包含非断行空格与全角空格。
private let groupTrimCharacters = "char(9,10,11,12,13,28,29,30,31,32,160,5760,8192,8193,8194,8195,8196,8197,8198,8199,8200,8201,8202,8232,8233,8239,8287,12288)"

extension Repository where Record == ReplaceRuleRow {
    public func list(groupName: String) async throws -> [ReplaceRuleRow] {
        try await database.writer.read { db in
            try ReplaceRuleRow.fetchAll(db, sql: """
                SELECT t2.* FROM replace_rules AS t2
                WHERE trim(:groupName, \(groupTrimCharacters)) <> '' AND EXISTS (
                    WITH RECURSIVE replace_rule_groups(group_name, rest) AS (
                        SELECT '', replace(replace(replace(coalesce(t2."group", ''), ';', ','), '，', ','), '；', ',') || ','
                        UNION ALL
                        SELECT trim(substr(rest, 1, instr(rest, ',') - 1), \(groupTrimCharacters)),
                               substr(rest, instr(rest, ',') + 1)
                        FROM replace_rule_groups WHERE rest <> ''
                    )
                    SELECT 1 FROM replace_rule_groups
                    WHERE group_name = trim(:groupName, \(groupTrimCharacters))
                )
                ORDER BY t2.sortOrder, t2.id
                """, arguments: ["groupName": groupName])
        }
    }

    public func listUngrouped() async throws -> [ReplaceRuleRow] {
        try await database.writer.read { db in
            try ReplaceRuleRow.fetchAll(db, sql: """
                SELECT * FROM replace_rules
                WHERE trim(coalesce("group", ''), \(groupTrimCharacters)) IN ('', '未分组')
                ORDER BY sortOrder, id
                """)
        }
    }

    public func get(id: Int64) async throws -> ReplaceRuleRow? {
        try await database.writer.read { db in try ReplaceRuleRow.fetchOne(db, key: id) }
    }

    public func list(enabled: Bool? = nil) async throws -> [ReplaceRuleRow] {
        try await database.writer.read { db in
            if let enabled {
                return try ReplaceRuleRow.fetchAll(db, sql: "SELECT * FROM replace_rules WHERE isEnabled = ? ORDER BY sortOrder, id", arguments: [enabled])
            }
            return try ReplaceRuleRow.fetchAll(db, sql: "SELECT * FROM replace_rules ORDER BY sortOrder, id")
        }
    }
}
