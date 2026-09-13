import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/rule/TocRule.kt.
public struct TocRule: Codable, Equatable, GsonRule {
    /// Kotlin 默认值：`null`（TocRule.kt:10）。
    public var preUpdateJs: String? = nil
    /// Kotlin 默认值：`null`（TocRule.kt:11）。
    public var chapterList: String? = nil
    /// Kotlin 默认值：`null`（TocRule.kt:12）。
    public var chapterName: String? = nil
    /// Kotlin 默认值：`null`（TocRule.kt:13）。
    public var chapterUrl: String? = nil
    /// Kotlin 默认值：`null`（TocRule.kt:14）。
    public var formatJs: String? = nil
    /// Kotlin 默认值：`null`（TocRule.kt:15）。
    public var isVolume: String? = nil
    /// Kotlin 默认值：`null`（TocRule.kt:16）。
    public var isVip: String? = nil
    /// Kotlin 默认值：`null`（TocRule.kt:17）。
    public var isPay: String? = nil
    /// Kotlin 默认值：`null`（TocRule.kt:18）。
    public var updateTime: String? = nil
    /// Kotlin 默认值：`null`（TocRule.kt:19）。
    public var nextTocUrl: String? = nil

    private enum CodingKeys: String, CodingKey {
        case preUpdateJs
        case chapterList
        case chapterName
        case chapterUrl
        case formatJs
        case isVolume
        case isVip
        case isPay
        case updateTime
        case nextTocUrl
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
        if container.contains(.preUpdateJs) {
            preUpdateJs = try container.gsonString(forKey: .preUpdateJs)
        }
        if container.contains(.chapterList) {
            chapterList = try container.gsonString(forKey: .chapterList)
        }
        if container.contains(.chapterName) {
            chapterName = try container.gsonString(forKey: .chapterName)
        }
        if container.contains(.chapterUrl) {
            chapterUrl = try container.gsonString(forKey: .chapterUrl)
        }
        if container.contains(.formatJs) {
            formatJs = try container.gsonString(forKey: .formatJs)
        }
        if container.contains(.isVolume) {
            isVolume = try container.gsonString(forKey: .isVolume)
        }
        if container.contains(.isVip) {
            isVip = try container.gsonString(forKey: .isVip)
        }
        if container.contains(.isPay) {
            isPay = try container.gsonString(forKey: .isPay)
        }
        if container.contains(.updateTime) {
            updateTime = try container.gsonString(forKey: .updateTime)
        }
        if container.contains(.nextTocUrl) {
            nextTocUrl = try container.gsonString(forKey: .nextTocUrl)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preUpdateJs, forKey: .preUpdateJs)
        try container.encode(chapterList, forKey: .chapterList)
        try container.encode(chapterName, forKey: .chapterName)
        try container.encode(chapterUrl, forKey: .chapterUrl)
        try container.encode(formatJs, forKey: .formatJs)
        try container.encode(isVolume, forKey: .isVolume)
        try container.encode(isVip, forKey: .isVip)
        try container.encode(isPay, forKey: .isPay)
        try container.encode(updateTime, forKey: .updateTime)
        try container.encode(nextTocUrl, forKey: .nextTocUrl)
    }

}
