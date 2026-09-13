import Foundation
import GRDB

public struct BookHighlight: StorageRow {
    public static let databaseTableName = "highlights"
    public var time: Int64 = 0
    public var bookUrl = ""
    public var chapterUrl = ""
    public var bookName = ""
    public var bookAuthor = ""
    public var chapterIndex = 0
    public var chapterPos = 0
    public var chapterPosEnd = 0
    public var layoutTitleLength = -1
    public var chapterName = ""
    public var bookText = ""
    public var style = ""
    public var note = ""

    public init() {}

    public func bodyStart(currentTitleLength: Int) -> Int {
        max(0, chapterPos - max(0, layoutTitleLength >= 0 ? layoutTitleLength : currentTitleLength))
    }

    public func bodyEnd(currentTitleLength: Int) -> Int {
        max(0, chapterPosEnd - max(0, layoutTitleLength >= 0 ? layoutTitleLength : currentTitleLength))
    }
}

public typealias BookHighlightRepository = Repository<BookHighlight>

extension Repository where Record == BookHighlight {
    public func list(bookURL: String, chapterIndex: Int) async throws -> [BookHighlight] {
        try await database.writer.read { db in
            try BookHighlight.fetchAll(db, sql: "SELECT * FROM highlights WHERE bookUrl = ? AND chapterIndex = ? ORDER BY chapterPos, time", arguments: [bookURL, chapterIndex])
        }
    }
}
