import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/Bookmark.kt.
public struct Bookmark: Codable, Equatable {
    /// Kotlin 默认值：`System.currentTimeMillis()`（Bookmark.kt:16）。
    public var time: Int64
    /// Kotlin 默认值：`""`（Bookmark.kt:17）。
    public var bookName: String? = ""
    /// Kotlin 默认值：`""`（Bookmark.kt:18）。
    public var bookAuthor: String? = ""
    /// Kotlin 默认值：`0`（Bookmark.kt:19）。
    public var chapterIndex: Int = 0
    /// Kotlin 默认值：`0`（Bookmark.kt:20）。
    public var chapterPos: Int = 0
    /// Kotlin 默认值：`""`（Bookmark.kt:21）。
    public var chapterName: String? = ""
    /// Kotlin 默认值：`""`（Bookmark.kt:22）。
    public var bookText: String? = ""
    /// Kotlin 默认值：`""`（Bookmark.kt:23）。
    public var content: String? = ""

    private enum CodingKeys: String, CodingKey {
        case time
        case bookName
        case bookAuthor
        case chapterIndex
        case chapterPos
        case chapterName
        case bookText
        case content
    }

    public init(now: Int64 = GsonDecoding.currentTimeMillis()) {
        time = now
    }

    public init(from decoder: Decoder) throws {
        self.init(now: GsonDecoding.time(from: decoder))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.gsonLong(forKey: .time) ?? time
        if container.contains(.bookName) {
            bookName = try container.gsonString(forKey: .bookName)
        }
        if container.contains(.bookAuthor) {
            bookAuthor = try container.gsonString(forKey: .bookAuthor)
        }
        chapterIndex = try container.gsonInt(forKey: .chapterIndex) ?? chapterIndex
        chapterPos = try container.gsonInt(forKey: .chapterPos) ?? chapterPos
        if container.contains(.chapterName) {
            chapterName = try container.gsonString(forKey: .chapterName)
        }
        if container.contains(.bookText) {
            bookText = try container.gsonString(forKey: .bookText)
        }
        if container.contains(.content) {
            content = try container.gsonString(forKey: .content)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(time, forKey: .time)
        try container.encode(bookName, forKey: .bookName)
        try container.encode(bookAuthor, forKey: .bookAuthor)
        try container.encode(chapterIndex, forKey: .chapterIndex)
        try container.encode(chapterPos, forKey: .chapterPos)
        try container.encode(chapterName, forKey: .chapterName)
        try container.encode(bookText, forKey: .bookText)
        try container.encode(content, forKey: .content)
    }

}
