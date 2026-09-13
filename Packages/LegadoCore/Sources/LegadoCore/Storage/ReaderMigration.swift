import GRDB

enum ReaderMigration {
    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v5") { db in
            try db.create(table: "highlights") { t in
                t.primaryKey("time", .integer)
                for name in ["bookUrl", "chapterUrl", "bookName", "bookAuthor", "chapterName", "bookText", "style", "note"] {
                    t.column(name, .text).notNull().defaults(to: "")
                }
                for name in ["chapterIndex", "chapterPos", "chapterPosEnd"] {
                    t.column(name, .integer).notNull().defaults(to: 0)
                }
                t.column("layoutTitleLength", .integer).notNull().defaults(to: -1)
            }
            try db.create(index: "index_highlights_bookUrl", on: "highlights", columns: ["bookUrl"])
        }
    }
}
