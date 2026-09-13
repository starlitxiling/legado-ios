import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/rule/SearchRule.kt.
public struct SearchRule: Codable, Equatable, GsonRule {
    /// Kotlin 默认值：`null`（SearchRule.kt:14）。
    public var checkKeyWord: String? = nil
    /// Kotlin 默认值：`null`（SearchRule.kt:15）。
    public var bookList: String? = nil
    /// Kotlin 默认值：`null`（SearchRule.kt:16）。
    public var name: String? = nil
    /// Kotlin 默认值：`null`（SearchRule.kt:17）。
    public var author: String? = nil
    /// Kotlin 默认值：`null`（SearchRule.kt:18）。
    public var intro: String? = nil
    /// Kotlin 默认值：`null`（SearchRule.kt:19）。
    public var kind: String? = nil
    /// Kotlin 默认值：`null`（SearchRule.kt:20）。
    public var lastChapter: String? = nil
    /// Kotlin 默认值：`null`（SearchRule.kt:21）。
    public var updateTime: String? = nil
    /// Kotlin 默认值：`null`（SearchRule.kt:22）。
    public var bookUrl: String? = nil
    /// Kotlin 默认值：`null`（SearchRule.kt:23）。
    public var coverUrl: String? = nil
    /// Kotlin 默认值：`null`（SearchRule.kt:24）。
    public var wordCount: String? = nil

    private enum CodingKeys: String, CodingKey {
        case checkKeyWord
        case bookList
        case name
        case author
        case intro
        case kind
        case lastChapter
        case updateTime
        case bookUrl
        case coverUrl
        case wordCount
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
        if container.contains(.checkKeyWord) {
            checkKeyWord = try container.gsonString(forKey: .checkKeyWord)
        }
        if container.contains(.bookList) {
            bookList = try container.gsonString(forKey: .bookList)
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
        if container.contains(.bookUrl) {
            bookUrl = try container.gsonString(forKey: .bookUrl)
        }
        if container.contains(.coverUrl) {
            coverUrl = try container.gsonString(forKey: .coverUrl)
        }
        if container.contains(.wordCount) {
            wordCount = try container.gsonString(forKey: .wordCount)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(checkKeyWord, forKey: .checkKeyWord)
        try container.encode(bookList, forKey: .bookList)
        try container.encode(name, forKey: .name)
        try container.encode(author, forKey: .author)
        try container.encode(intro, forKey: .intro)
        try container.encode(kind, forKey: .kind)
        try container.encode(lastChapter, forKey: .lastChapter)
        try container.encode(updateTime, forKey: .updateTime)
        try container.encode(bookUrl, forKey: .bookUrl)
        try container.encode(coverUrl, forKey: .coverUrl)
        try container.encode(wordCount, forKey: .wordCount)
    }

}
