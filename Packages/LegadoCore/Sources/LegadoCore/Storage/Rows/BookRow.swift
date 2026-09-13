import GRDB

/// Kotlin cb664b84d: data/entities/Book.kt。
public struct BookRow: StorageRow {
    public static let databaseTableName = "books"
    public var `bookUrl`: String = ""
    public var `tocUrl`: String = ""
    public var `origin`: String = "loc_book"
    public var `originName`: String = ""
    public var `name`: String = ""
    public var `author`: String = ""
    public var `kind`: String? = nil
    public var `customTag`: String? = nil
    public var `coverUrl`: String? = nil
    public var `customCoverUrl`: String? = nil
    public var `intro`: String? = nil
    public var `customIntro`: String? = nil
    public var `charset`: String? = nil
    public var `type`: Int = 8
    public var `group`: Int64 = 0
    public var `latestChapterTitle`: String? = nil
    public var `latestChapterTime`: Int64 = 0
    public var `lastCheckTime`: Int64 = 0
    public var `lastCheckCount`: Int = 0
    public var `totalChapterNum`: Int = 0
    public var `durChapterTitle`: String? = nil
    public var `durChapterIndex`: Int = 0
    public var `durVolumeIndex`: Int = 0
    public var `chapterInVolumeIndex`: Int = 0
    public var `durChapterPos`: Int = 0
    public var `durChapterTime`: Int64 = 0
    public var `wordCount`: String? = nil
    public var `canUpdate`: Bool = true
    public var `order`: Int = 0
    public var `originOrder`: Int = 0
    public var `variable`: String? = nil
    /// Room TypeConverter 的 JSON 文本。
    public var `readConfig`: String? = nil
    public var `syncTime`: Int64 = 0
    public var `persistedCoverUrl`: String? = nil

    public init() {}
}
