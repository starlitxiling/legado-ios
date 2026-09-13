import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/BookChapter.kt.
public struct BookChapter: Codable, Equatable {
    /// Kotlin 默认值：`""`（BookChapter.kt:43）。
    public var url: String? = ""
    /// Kotlin 默认值：`""`（BookChapter.kt:44）。
    public var title: String? = ""
    /// Kotlin 默认值：`false`（BookChapter.kt:45）。
    public var isVolume: Bool = false
    /// Kotlin 默认值：`""`（BookChapter.kt:46）。
    public var baseUrl: String? = ""
    /// Kotlin 默认值：`""`（BookChapter.kt:47）。
    public var bookUrl: String? = ""
    /// Kotlin 默认值：`0`（BookChapter.kt:48）。
    public var index: Int = 0
    /// Kotlin 默认值：`false`（BookChapter.kt:49）。
    public var isVip: Bool = false
    /// Kotlin 默认值：`false`（BookChapter.kt:50）。
    public var isPay: Bool = false
    /// Kotlin 默认值：`null`（BookChapter.kt:51）。
    public var resourceUrl: String? = nil
    /// Kotlin 默认值：`null`（BookChapter.kt:52）。
    public var tag: String? = nil
    /// Kotlin 默认值：`null`（BookChapter.kt:53）。
    public var wordCount: String? = nil
    /// Kotlin 默认值：`null`（BookChapter.kt:54）。
    public var start: Int64? = nil
    /// Kotlin 默认值：`null`（BookChapter.kt:55）。
    public var end: Int64? = nil
    /// Kotlin 默认值：`null`（BookChapter.kt:56）。
    public var startFragmentId: String? = nil
    /// Kotlin 默认值：`null`（BookChapter.kt:57）。
    public var endFragmentId: String? = nil
    /// Kotlin 默认值：`null`（BookChapter.kt:58）。
    public var variable: String? = nil
    /// Kotlin 默认值：`null`（BookChapter.kt:59）。
    public var imgUrl: String? = nil

    private enum CodingKeys: String, CodingKey {
        case url
        case title
        case isVolume
        case baseUrl
        case bookUrl
        case index
        case isVip
        case isPay
        case resourceUrl
        case tag
        case wordCount
        case start
        case end
        case startFragmentId
        case endFragmentId
        case variable
        case imgUrl
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.url) {
            url = try container.gsonString(forKey: .url)
        }
        if container.contains(.title) {
            title = try container.gsonString(forKey: .title)
        }
        isVolume = try container.gsonBool(forKey: .isVolume) ?? isVolume
        if container.contains(.baseUrl) {
            baseUrl = try container.gsonString(forKey: .baseUrl)
        }
        if container.contains(.bookUrl) {
            bookUrl = try container.gsonString(forKey: .bookUrl)
        }
        index = try container.gsonInt(forKey: .index) ?? index
        isVip = try container.gsonBool(forKey: .isVip) ?? isVip
        isPay = try container.gsonBool(forKey: .isPay) ?? isPay
        if container.contains(.resourceUrl) {
            resourceUrl = try container.gsonString(forKey: .resourceUrl)
        }
        if container.contains(.tag) {
            tag = try container.gsonString(forKey: .tag)
        }
        if container.contains(.wordCount) {
            wordCount = try container.gsonString(forKey: .wordCount)
        }
        if container.contains(.start) {
            start = try container.gsonLong(forKey: .start)
        }
        if container.contains(.end) {
            end = try container.gsonLong(forKey: .end)
        }
        if container.contains(.startFragmentId) {
            startFragmentId = try container.gsonString(forKey: .startFragmentId)
        }
        if container.contains(.endFragmentId) {
            endFragmentId = try container.gsonString(forKey: .endFragmentId)
        }
        if container.contains(.variable) {
            variable = try container.gsonString(forKey: .variable)
        }
        if container.contains(.imgUrl) {
            imgUrl = try container.gsonString(forKey: .imgUrl)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(isVolume, forKey: .isVolume)
        try container.encode(baseUrl, forKey: .baseUrl)
        try container.encode(bookUrl, forKey: .bookUrl)
        try container.encode(index, forKey: .index)
        try container.encode(isVip, forKey: .isVip)
        try container.encode(isPay, forKey: .isPay)
        try container.encode(resourceUrl, forKey: .resourceUrl)
        try container.encode(tag, forKey: .tag)
        try container.encode(wordCount, forKey: .wordCount)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(startFragmentId, forKey: .startFragmentId)
        try container.encode(endFragmentId, forKey: .endFragmentId)
        try container.encode(variable, forKey: .variable)
        try container.encode(imgUrl, forKey: .imgUrl)
    }

}
