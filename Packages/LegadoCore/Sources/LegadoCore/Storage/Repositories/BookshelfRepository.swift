import GRDB

public typealias BookshelfRepository = Repository<BookRow>

public enum BookshelfSort: Sendable {
    case lastRead, latestUpdate, manual, name

    var sql: String {
        switch self {
        case .lastRead: return "durChapterTime DESC, bookUrl"
        case .latestUpdate: return "latestChapterTime DESC, bookUrl"
        case .manual: return "\"order\", bookUrl"
        case .name: return "name, author, bookUrl"
        }
    }
}

extension Repository where Record == BookRow {
    /// 导入时对齐 Room REPLACE；同名同作者的旧 URL 及其章节会被删除。
    public func replaceByIdentity(_ books: [BookRow]) async throws {
        try await database.writer.write { db in
            for var book in books {
                try book.insert(db, onConflict: .replace)
            }
        }
    }

    public func get(bookUrl: String) async throws -> BookRow? {
        try await database.writer.read { db in try BookRow.fetchOne(db, key: bookUrl) }
    }

    /// 正分组使用位掩码；负分组 ID 对齐 Kotlin BookGroup 的内置分组。
    public func list(groupID: Int64 = -1, sort: BookshelfSort = .lastRead) async throws -> [BookRow] {
        try await database.writer.read { db in
            var filter = "(type & 1024) = 0"
            var arguments: StatementArguments = []
            let ungrouped = "((SELECT coalesce(sum(groupId), 0) FROM book_groups WHERE groupId > 0) & \"group\") = 0"
            switch groupID {
            case -1: break
            case -2: filter += " AND (type & 256) > 0"
            case -3: filter += " AND (type & 32) > 0"
            case -6: filter += " AND (type & 4) > 0"
            case -11: filter += " AND (type & 16) > 0"
            case -4: filter += " AND (type & 292) = 0 AND \(ungrouped)"
            case -5: filter += " AND (type & 256) > 0 AND \(ungrouped)"
            case -100:
                filter += " AND (type & 8) > 0 AND (type & 256) = 0 AND \(ungrouped) AND coalesce((SELECT show FROM book_groups WHERE groupId = -4), 0) != 1"
            default:
                filter += " AND (\"group\" & ?) > 0"
                arguments = [groupID]
            }
            return try BookRow.fetchAll(db, sql: "SELECT * FROM books WHERE \(filter) ORDER BY \(sort.sql)", arguments: arguments)
        }
    }

    @discardableResult
    public func updateProgress(bookUrl: String, chapterIndex: Int, chapterPos: Int,
                               chapterTitle: String?, readTime: Int64) async throws -> Bool {
        try await database.writer.write { db in
            try db.execute(sql: """
                UPDATE books SET durChapterIndex = ?, durChapterPos = ?, durChapterTitle = ?, durChapterTime = ?
                WHERE bookUrl = ?
                """, arguments: [chapterIndex, chapterPos, chapterTitle, readTime, bookUrl])
            return db.changesCount > 0
        }
    }
}
