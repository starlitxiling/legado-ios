import GRDB

/// Kotlin cb664b84d: data/entities/ReadRecord.kt。
public struct ReadRecordRow: StorageRow {
    public static let databaseTableName = "readRecord"
    public var `deviceId`: String = ""
    public var `bookName`: String = ""
    public var `author`: String = ""
    public var `readTime`: Int64 = 0
    public var `lastRead`: Int64 = 0
    public var `lastChapterTitle`: String? = nil
    public var `lastChapterIndex`: Int = -1
    public var `lastChapterPos`: Int = 0
    public var `coverUrl`: String? = nil
    public var `resolvedAuthor`: String? = nil

    public init() {}
}
