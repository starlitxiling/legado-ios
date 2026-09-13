import GRDB

extension BookRow {
    public static func matching(bookUrl: String, name: String, author: String, in db: Database) throws -> BookRow? {
        try BookRow.fetchOne(db, key: bookUrl)
            ?? BookRow.fetchOne(db, sql: "SELECT * FROM books WHERE name = ? AND author = ?", arguments: [name, author])
    }

    public func replaceByIdentity(in db: Database) throws {
        var row = self
        try row.insert(db, onConflict: .replace)
    }

    public func save(in db: Database) throws {
        var row = self
        try row.save(db)
    }

    public func updateProgress(in db: Database) throws {
        try db.execute(sql: """
            UPDATE books SET durChapterIndex = ?, durChapterPos = ?, durChapterTitle = ?, durChapterTime = ?
            WHERE bookUrl = ?
            """, arguments: [durChapterIndex, durChapterPos, durChapterTitle, durChapterTime, bookUrl])
    }
}

extension BookChapterRow {
    public static func replaceAll(bookUrl: String, chapters: [BookChapterRow], in db: Database) throws {
        guard chapters.allSatisfy({ $0.bookUrl == bookUrl }) else { throw StorageError.chapterBookMismatch }
        try db.execute(sql: "DELETE FROM chapters WHERE bookUrl = ?", arguments: [bookUrl])
        for var chapter in chapters { try chapter.insert(db) }
    }
}
