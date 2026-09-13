import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/rule/ContentRule.kt.
public struct ContentRule: Codable, Equatable, GsonRule {
    /// Kotlin 默认值：`null`（ContentRule.kt:13）。
    public var content: String? = nil
    /// Kotlin 默认值：`null`（ContentRule.kt:14）。
    public var subContent: String? = nil
    /// Kotlin 默认值：`null`（ContentRule.kt:15）。
    public var title: String? = nil
    /// Kotlin 默认值：`null`（ContentRule.kt:16）。
    public var nextContentUrl: String? = nil
    /// Kotlin 默认值：`null`（ContentRule.kt:17）。
    public var webJs: String? = nil
    /// Kotlin 默认值：`null`（ContentRule.kt:18）。
    public var sourceRegex: String? = nil
    /// Kotlin 默认值：`null`（ContentRule.kt:19）。
    public var replaceRegex: String? = nil
    /// Kotlin 默认值：`null`（ContentRule.kt:20）。
    public var imageStyle: String? = nil
    /// Kotlin 默认值：`null`（ContentRule.kt:21）。
    public var imageDecode: String? = nil
    /// Kotlin 默认值：`null`（ContentRule.kt:22）。
    public var payAction: String? = nil
    /// Kotlin 默认值：`null`（ContentRule.kt:24）。
    public var callBackJs: String? = nil
    /// Kotlin 默认值：`null`（ContentRule.kt:25）。
    public var contentBatch: String? = nil
    /// Kotlin 默认值：`null`（ContentRule.kt:26）。
    public var maxBatchSize: Int? = nil

    private enum CodingKeys: String, CodingKey {
        case content
        case subContent
        case title
        case nextContentUrl
        case webJs
        case sourceRegex
        case replaceRegex
        case imageStyle
        case imageDecode
        case payAction
        case callBackJs
        case contentBatch
        case maxBatchSize
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
        if container.contains(.content) {
            content = try container.gsonString(forKey: .content)
        }
        if container.contains(.subContent) {
            subContent = try container.gsonString(forKey: .subContent)
        }
        if container.contains(.title) {
            title = try container.gsonString(forKey: .title)
        }
        if container.contains(.nextContentUrl) {
            nextContentUrl = try container.gsonString(forKey: .nextContentUrl)
        }
        if container.contains(.webJs) {
            webJs = try container.gsonString(forKey: .webJs)
        }
        if container.contains(.sourceRegex) {
            sourceRegex = try container.gsonString(forKey: .sourceRegex)
        }
        if container.contains(.replaceRegex) {
            replaceRegex = try container.gsonString(forKey: .replaceRegex)
        }
        if container.contains(.imageStyle) {
            imageStyle = try container.gsonString(forKey: .imageStyle)
        }
        if container.contains(.imageDecode) {
            imageDecode = try container.gsonString(forKey: .imageDecode)
        }
        if container.contains(.payAction) {
            payAction = try container.gsonString(forKey: .payAction)
        }
        if container.contains(.callBackJs) {
            callBackJs = try container.gsonString(forKey: .callBackJs)
        }
        if container.contains(.contentBatch) {
            contentBatch = try container.gsonString(forKey: .contentBatch)
        }
        if container.contains(.maxBatchSize) {
            maxBatchSize = try container.gsonBoxedInt(forKey: .maxBatchSize, tree: decoder.userInfo[GsonDecoding.ruleStringKey] as? Bool != true)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(content, forKey: .content)
        try container.encode(subContent, forKey: .subContent)
        try container.encode(title, forKey: .title)
        try container.encode(nextContentUrl, forKey: .nextContentUrl)
        try container.encode(webJs, forKey: .webJs)
        try container.encode(sourceRegex, forKey: .sourceRegex)
        try container.encode(replaceRegex, forKey: .replaceRegex)
        try container.encode(imageStyle, forKey: .imageStyle)
        try container.encode(imageDecode, forKey: .imageDecode)
        try container.encode(payAction, forKey: .payAction)
        try container.encode(callBackJs, forKey: .callBackJs)
        try container.encode(contentBatch, forKey: .contentBatch)
        try container.encode(maxBatchSize, forKey: .maxBatchSize)
    }

}
