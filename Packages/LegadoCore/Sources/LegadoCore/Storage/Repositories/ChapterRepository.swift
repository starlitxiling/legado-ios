import GRDB

public typealias ChapterRepository = Repository<BookChapterRow>

public enum StorageError: Error, Equatable {
    case chapterBookMismatch
}

extension Repository where Record == BookChapterRow {
    public func get(bookUrl: String, index: Int) async throws -> BookChapterRow? {
        try await database.writer.read { db in
            try BookChapterRow.fetchOne(db, sql: "SELECT * FROM chapters WHERE bookUrl = ? AND \"index\" = ?", arguments: [bookUrl, index])
        }
    }

    public func list(bookUrl: String) async throws -> [BookChapterRow] {
        try await database.writer.read { db in
            try BookChapterRow.fetchAll(db, sql: "SELECT * FROM chapters WHERE bookUrl = ? ORDER BY \"index\"", arguments: [bookUrl])
        }
    }

    public func deleteAll(bookUrl: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM chapters WHERE bookUrl = ?", arguments: [bookUrl])
        }
    }

    public func replaceAll(bookUrl: String, chapters: [BookChapterRow]) async throws {
        guard chapters.allSatisfy({ $0.bookUrl == bookUrl }) else { throw StorageError.chapterBookMismatch }
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM chapters WHERE bookUrl = ?", arguments: [bookUrl])
            for var chapter in chapters { try chapter.insert(db) }
        }
    }
}
