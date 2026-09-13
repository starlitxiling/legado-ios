import GRDB

public typealias BookmarkRepository = Repository<BookmarkRow>

extension Repository where Record == BookmarkRow {
    public func get(time: Int64) async throws -> BookmarkRow? {
        try await database.writer.read { db in try BookmarkRow.fetchOne(db, key: time) }
    }

    public func list(bookName: String, bookAuthor: String) async throws -> [BookmarkRow] {
        try await database.writer.read { db in
            try BookmarkRow.fetchAll(db, sql: "SELECT * FROM bookmarks WHERE bookName = ? AND bookAuthor = ? ORDER BY chapterIndex, chapterPos, time", arguments: [bookName, bookAuthor])
        }
    }
}
