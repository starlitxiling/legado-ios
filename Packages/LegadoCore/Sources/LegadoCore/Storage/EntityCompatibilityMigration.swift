import GRDB

enum EntityCompatibilityMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v7_entities") { db in
            try db.create(table: "search_keywords") { t in
                t.column("word", .text).notNull()
                t.column("usage", .integer).notNull()
                t.column("lastUseTime", .integer).notNull()
                t.primaryKey(["word"])
            }
            try db.create(table: "highlightRules") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull()
                t.column("name", .text).notNull()
                t.column("pattern", .text).notNull()
                t.column("isRegex", .boolean).notNull()
                t.column("scope", .text)
                t.column("isEnabled", .boolean).notNull()
                t.column("style", .text).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("timeoutMillisecond", .integer).notNull()
                t.column("group", .text)
                t.column("applyToTitle", .boolean).notNull()
                t.column("applyToBody", .boolean).notNull()
            }
            try db.create(table: "servers") { t in
                t.column("id", .integer).notNull()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("config", .text)
                t.column("sortNumber", .integer).notNull()
                t.primaryKey(["id"])
            }
            try db.create(table: "keyboardAssists") { t in
                t.column("type", .integer).notNull()
                t.column("key", .text).notNull()
                t.column("value", .text).notNull()
                t.column("serialNo", .integer).notNull()
                t.primaryKey(["type", "key"])
            }
            try db.create(table: "ruleSubs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("url", .text).notNull()
                t.column("type", .integer).notNull()
                t.column("customOrder", .integer).notNull()
                t.column("autoUpdate", .boolean).notNull()
                t.column("update", .integer).notNull()
                t.column("updateInterval", .integer).notNull()
                t.column("silentUpdate", .boolean).notNull()
                t.column("js", .text)
                t.column("showRule", .text)
                t.column("sourceUrl", .text)
            }
            try db.create(table: "caches") { t in
                t.column("key", .text).notNull()
                t.column("value", .text)
                t.column("deadline", .integer).notNull()
                t.primaryKey(["key"])
            }
            try db.create(table: "auto_task_rules") { t in
                t.column("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("enable", .boolean).notNull()
                t.column("cron", .text)
                t.column("loginUrl", .text)
                t.column("loginUi", .text)
                t.column("loginCheckJs", .text)
                t.column("comment", .text)
                t.column("script", .text).notNull()
                t.column("header", .text)
                t.column("jsLib", .text)
                t.column("concurrentRate", .text)
                t.column("enabledCookieJar", .boolean).notNull()
                t.column("customOrder", .integer).notNull()
                t.column("lastRunAt", .integer).notNull()
                t.column("lastResult", .text)
                t.column("lastError", .text)
                t.column("lastLog", .text)
                t.primaryKey(["id"])
            }
            try db.create(table: "book_memos") { t in
                t.column("bookUrl", .text).notNull()
                t.column("content", .text).notNull()
                t.column("updatedAt", .integer).notNull()
                t.primaryKey(["bookUrl"])
            }
            try db.create(index: "index_highlightRules_uuid", on: "highlightRules", columns: ["uuid"], unique: true)
            try db.create(index: "index_auto_task_rules_order", on: "auto_task_rules", columns: ["enable", "customOrder"])
            try db.create(table: "backup_files") { t in
                t.primaryKey("name", .text)
                t.column("data", .blob).notNull()
            }
            try db.create(table: "book_source_check_states") { t in
                t.primaryKey("bookSourceUrl", .text).references("book_sources", column: "bookSourceUrl", onDelete: .cascade)
                for name in ["revision", "sourceRevision", "status", "detail"] { t.column(name, .text).notNull() }
                t.column("checkedAt", .integer).notNull()
            }
        }
    }
}
