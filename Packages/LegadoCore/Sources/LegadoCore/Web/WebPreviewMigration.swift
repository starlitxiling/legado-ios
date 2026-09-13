import GRDB

enum WebPreviewMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("web_replace_preview_text") { db in
            try db.alter(table: "replace_rules") { table in
                table.add(column: "previewText", .text)
            }
        }
    }
}
