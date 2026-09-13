import GRDB

/// Kotlin cb664b84d: data/entities/BookChapter.kt。
public struct BookChapterRow: StorageRow {
    public static let databaseTableName = "chapters"
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .abort)
    public var `url`: String = ""
    public var `title`: String = ""
    public var `isVolume`: Bool = false
    public var `baseUrl`: String = ""
    public var `bookUrl`: String = ""
    public var `index`: Int = 0
    public var `isVip`: Bool = false
    public var `isPay`: Bool = false
    public var `resourceUrl`: String? = nil
    public var `tag`: String? = nil
    public var `wordCount`: String? = nil
    public var `start`: Int64? = nil
    public var `end`: Int64? = nil
    public var `startFragmentId`: String? = nil
    public var `endFragmentId`: String? = nil
    public var `variable`: String? = nil
    public var `imgUrl`: String? = nil

    public init() {}
}
