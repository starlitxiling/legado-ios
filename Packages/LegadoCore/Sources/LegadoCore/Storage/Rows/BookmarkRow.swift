import GRDB

/// Kotlin cb664b84d: data/entities/Bookmark.kt。
public struct BookmarkRow: StorageRow {
    public static let databaseTableName = "bookmarks"
    public var `time`: Int64 = 0
    public var `bookName`: String = ""
    public var `bookAuthor`: String = ""
    public var `chapterIndex`: Int = 0
    public var `chapterPos`: Int = 0
    public var `chapterName`: String = ""
    public var `bookText`: String = ""
    public var `content`: String = ""

    public init() {}
}
