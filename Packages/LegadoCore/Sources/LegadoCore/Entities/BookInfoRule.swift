import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/rule/BookInfoRule.kt.
public struct BookInfoRule: Codable, Equatable, GsonRule {
    /// Kotlin 默认值：`null`（BookInfoRule.kt:13）。
    public var `init`: String? = nil
    /// Kotlin 默认值：`null`（BookInfoRule.kt:14）。
    public var name: String? = nil
    /// Kotlin 默认值：`null`（BookInfoRule.kt:15）。
    public var author: String? = nil
    /// Kotlin 默认值：`null`（BookInfoRule.kt:16）。
    public var intro: String? = nil
    /// Kotlin 默认值：`null`（BookInfoRule.kt:17）。
    public var kind: String? = nil
    /// Kotlin 默认值：`null`（BookInfoRule.kt:18）。
    public var lastChapter: String? = nil
    /// Kotlin 默认值：`null`（BookInfoRule.kt:19）。
    public var updateTime: String? = nil
    /// Kotlin 默认值：`null`（BookInfoRule.kt:20）。
    public var coverUrl: String? = nil
    /// Kotlin 默认值：`null`（BookInfoRule.kt:21）。
    public var tocUrl: String? = nil
    /// Kotlin 默认值：`null`（BookInfoRule.kt:22）。
    public var wordCount: String? = nil
    /// Kotlin 默认值：`null`（BookInfoRule.kt:23）。
    public var canReName: String? = nil
    /// Kotlin 默认值：`null`（BookInfoRule.kt:24）。
    public var downloadUrls: String? = nil

    private enum CodingKeys: String, CodingKey {
        case `init`
        case name
        case author
        case intro
        case kind
        case lastChapter
        case updateTime
        case coverUrl
        case tocUrl
        case wordCount
        case canReName
        case downloadUrls
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let single = try decoder.singleValueContainer()
        if let text = try? single.decode(String.self) {
            guard case .object = try GsonValue.parse(Data(text.utf8)) else {
                throw DecodingError.typeMismatch(Self.self, .init(codingPath: decoder.codingPath, debugDescription: "规则字符串必须包含对象"))
            }
            self = try GsonJSONDecoder(now: { GsonDecoding.time(from: decoder) }).decodeRuleString(Self.self, from: Data(text.utf8))
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.`init`) {
            self.`init` = try container.gsonString(forKey: .`init`)
        }
        if container.contains(.name) {
            name = try container.gsonString(forKey: .name)
        }
        if container.contains(.author) {
            author = try container.gsonString(forKey: .author)
        }
        if container.contains(.intro) {
            intro = try container.gsonString(forKey: .intro)
        }
        if container.contains(.kind) {
            kind = try container.gsonString(forKey: .kind)
        }
        if container.contains(.lastChapter) {
            lastChapter = try container.gsonString(forKey: .lastChapter)
        }
        if container.contains(.updateTime) {
            updateTime = try container.gsonString(forKey: .updateTime)
        }
        if container.contains(.coverUrl) {
            coverUrl = try container.gsonString(forKey: .coverUrl)
        }
        if container.contains(.tocUrl) {
            tocUrl = try container.gsonString(forKey: .tocUrl)
        }
        if container.contains(.wordCount) {
            wordCount = try container.gsonString(forKey: .wordCount)
        }
        if container.contains(.canReName) {
            canReName = try container.gsonString(forKey: .canReName)
        }
        if container.contains(.downloadUrls) {
            downloadUrls = try container.gsonString(forKey: .downloadUrls)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.`init`, forKey: .`init`)
        try container.encode(name, forKey: .name)
        try container.encode(author, forKey: .author)
        try container.encode(intro, forKey: .intro)
        try container.encode(kind, forKey: .kind)
        try container.encode(lastChapter, forKey: .lastChapter)
        try container.encode(updateTime, forKey: .updateTime)
        try container.encode(coverUrl, forKey: .coverUrl)
        try container.encode(tocUrl, forKey: .tocUrl)
        try container.encode(wordCount, forKey: .wordCount)
        try container.encode(canReName, forKey: .canReName)
        try container.encode(downloadUrls, forKey: .downloadUrls)
    }

}
