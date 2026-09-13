import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/SearchBook.kt.
public struct SearchBook: Codable, Equatable {
    /// Kotlin 默认值：`""`（SearchBook.kt:32）。
    public var bookUrl: String? = ""
    /// Kotlin 默认值：`""`（SearchBook.kt:34）。
    public var origin: String? = ""
    /// Kotlin 默认值：`""`（SearchBook.kt:35）。
    public var originName: String? = ""
    /// Kotlin 默认值：`BookType.text`（SearchBook.kt:37）。
    public var type: Int = 8
    /// Kotlin 默认值：`""`（SearchBook.kt:38）。
    public var name: String? = ""
    /// Kotlin 默认值：`""`（SearchBook.kt:39）。
    public var author: String? = ""
    /// Kotlin 默认值：`null`（SearchBook.kt:40）。
    public var kind: String? = nil
    /// Kotlin 默认值：`null`（SearchBook.kt:41）。
    public var coverUrl: String? = nil
    /// Kotlin 默认值：`null`（SearchBook.kt:42）。
    public var intro: String? = nil
    /// Kotlin 默认值：`null`（SearchBook.kt:43）。
    public var wordCount: String? = nil
    /// Kotlin 默认值：`null`（SearchBook.kt:44）。
    public var latestChapterTitle: String? = nil
    /// Kotlin 默认值：`""`（SearchBook.kt:46）。
    public var tocUrl: String? = ""
    /// Kotlin 默认值：`System.currentTimeMillis()`（SearchBook.kt:47）。
    public var time: Int64
    /// Kotlin 默认值：`null`（SearchBook.kt:48）。
    public var variable: String? = nil
    /// Kotlin 默认值：`0`（SearchBook.kt:49）。
    public var originOrder: Int = 0
    /// Kotlin 默认值：`null`（SearchBook.kt:50）。
    public var chapterWordCountText: String? = nil
    /// Kotlin 默认值：`-1`（SearchBook.kt:52）。
    public var chapterWordCount: Int = -1
    /// Kotlin 默认值：`-1`（SearchBook.kt:54）。
    public var respondTime: Int = -1

    private enum CodingKeys: String, CodingKey {
        case bookUrl
        case origin
        case originName
        case type
        case name
        case author
        case kind
        case coverUrl
        case intro
        case wordCount
        case latestChapterTitle
        case tocUrl
        case time
        case variable
        case originOrder
        case chapterWordCountText
        case chapterWordCount
        case respondTime
    }

    public init(now: Int64 = GsonDecoding.currentTimeMillis()) {
        time = now
    }

    public init(from decoder: Decoder) throws {
        self.init(now: GsonDecoding.time(from: decoder))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.bookUrl) {
            bookUrl = try container.gsonString(forKey: .bookUrl)
        }
        if container.contains(.origin) {
            origin = try container.gsonString(forKey: .origin)
        }
        if container.contains(.originName) {
            originName = try container.gsonString(forKey: .originName)
        }
        type = try container.gsonInt(forKey: .type) ?? type
        if container.contains(.name) {
            name = try container.gsonString(forKey: .name)
        }
        if container.contains(.author) {
            author = try container.gsonString(forKey: .author)
        }
        if container.contains(.kind) {
            kind = try container.gsonString(forKey: .kind)
        }
        if container.contains(.coverUrl) {
            coverUrl = try container.gsonString(forKey: .coverUrl)
        }
        if container.contains(.intro) {
            intro = try container.gsonString(forKey: .intro)
        }
        if container.contains(.wordCount) {
            wordCount = try container.gsonString(forKey: .wordCount)
        }
        if container.contains(.latestChapterTitle) {
            latestChapterTitle = try container.gsonString(forKey: .latestChapterTitle)
        }
        if container.contains(.tocUrl) {
            tocUrl = try container.gsonString(forKey: .tocUrl)
        }
        time = try container.gsonLong(forKey: .time) ?? time
        if container.contains(.variable) {
            variable = try container.gsonString(forKey: .variable)
        }
        originOrder = try container.gsonInt(forKey: .originOrder) ?? originOrder
        if container.contains(.chapterWordCountText) {
            chapterWordCountText = try container.gsonString(forKey: .chapterWordCountText)
        }
        chapterWordCount = try container.gsonInt(forKey: .chapterWordCount) ?? chapterWordCount
        respondTime = try container.gsonInt(forKey: .respondTime) ?? respondTime
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bookUrl, forKey: .bookUrl)
        try container.encode(origin, forKey: .origin)
        try container.encode(originName, forKey: .originName)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(author, forKey: .author)
        try container.encode(kind, forKey: .kind)
        try container.encode(coverUrl, forKey: .coverUrl)
        try container.encode(intro, forKey: .intro)
        try container.encode(wordCount, forKey: .wordCount)
        try container.encode(latestChapterTitle, forKey: .latestChapterTitle)
        try container.encode(tocUrl, forKey: .tocUrl)
        try container.encode(time, forKey: .time)
        try container.encode(variable, forKey: .variable)
        try container.encode(originOrder, forKey: .originOrder)
        try container.encode(chapterWordCountText, forKey: .chapterWordCountText)
        try container.encode(chapterWordCount, forKey: .chapterWordCount)
        try container.encode(respondTime, forKey: .respondTime)
    }

}
