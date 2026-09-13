import GRDB

/// Kotlin cb664b84d: data/entities/SearchBook.kt。
public struct SearchBookRow: StorageRow {
    public static let databaseTableName = "searchBooks"
    public var `bookUrl`: String = ""
    public var `origin`: String = ""
    public var `originName`: String = ""
    public var `type`: Int = 8
    public var `name`: String = ""
    public var `author`: String = ""
    public var `kind`: String? = nil
    public var `coverUrl`: String? = nil
    public var `intro`: String? = nil
    public var `wordCount`: String? = nil
    public var `latestChapterTitle`: String? = nil
    public var `tocUrl`: String = ""
    public var `time`: Int64 = 0
    public var `variable`: String? = nil
    public var `originOrder`: Int = 0
    public var `chapterWordCountText`: String? = nil
    public var `chapterWordCount`: Int = -1
    public var `respondTime`: Int = -1

    public init() {}
}
