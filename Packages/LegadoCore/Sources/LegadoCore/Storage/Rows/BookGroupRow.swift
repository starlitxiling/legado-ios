import GRDB

/// Kotlin cb664b84d: data/entities/BookGroup.kt。
public struct BookGroupRow: StorageRow {
    public static let databaseTableName = "book_groups"
    public var `groupId`: Int64 = 1
    public var `groupName`: String = ""
    public var `cover`: String? = nil
    public var `order`: Int = 0
    public var `enableRefresh`: Bool = true
    public var `show`: Bool = true
    public var `bookSort`: Int = -1
    public var `onlyUpdateRead`: Bool = false

    public init() {}
}
