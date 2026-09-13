import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/rule/ReviewRule.kt.
public struct ReviewRule: Codable, Equatable, GsonRule {
    /// Kotlin 默认值：`null`（ReviewRule.kt:10）。
    public var reviewUrl: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:11）。
    public var avatarRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:12）。
    public var contentRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:13）。
    public var postTimeRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:14）。
    public var reviewQuoteUrl: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:17）。
    public var voteUpUrl: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:18）。
    public var voteDownUrl: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:19）。
    public var postReviewUrl: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:20）。
    public var postQuoteUrl: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:21）。
    public var deleteUrl: String? = nil
    /// Kotlin 默认值：`false`（ReviewRule.kt:22）。
    public var enabled: Bool = false
    /// Kotlin 默认值：`null`（ReviewRule.kt:23）。
    public var reviewSummaryUrl: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:24）。
    public var summaryListRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:25）。
    public var summaryParagraphIndexRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:26）。
    public var summaryParagraphDataRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:27）。
    public var summaryCountRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:28）。
    public var reviewDetailUrl: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:29）。
    public var reviewDetailNextPageUrl: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:30）。
    public var detailListRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:31）。
    public var detailIdRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:32）。
    public var detailAvatarRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:33）。
    public var detailNameRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:34）。
    public var detailBadgeRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:35）。
    public var detailContentRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:36）。
    public var replyListRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:37）。
    public var replyIdRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:38）。
    public var replyAvatarRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:39）。
    public var replyNameRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:40）。
    public var replyBadgeRule: String? = nil
    /// Kotlin 默认值：`null`（ReviewRule.kt:41）。
    public var replyContentRule: String? = nil

    private enum CodingKeys: String, CodingKey {
        case reviewUrl
        case avatarRule
        case contentRule
        case postTimeRule
        case reviewQuoteUrl
        case voteUpUrl
        case voteDownUrl
        case postReviewUrl
        case postQuoteUrl
        case deleteUrl
        case enabled
        case reviewSummaryUrl
        case summaryListRule
        case summaryParagraphIndexRule
        case summaryParagraphDataRule
        case summaryCountRule
        case reviewDetailUrl
        case reviewDetailNextPageUrl
        case detailListRule
        case detailIdRule
        case detailAvatarRule
        case detailNameRule
        case detailBadgeRule
        case detailContentRule
        case replyListRule
        case replyIdRule
        case replyAvatarRule
        case replyNameRule
        case replyBadgeRule
        case replyContentRule
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
        if container.contains(.reviewUrl) {
            reviewUrl = try container.gsonString(forKey: .reviewUrl)
        }
        if container.contains(.avatarRule) {
            avatarRule = try container.gsonString(forKey: .avatarRule)
        }
        if container.contains(.contentRule) {
            contentRule = try container.gsonString(forKey: .contentRule)
        }
        if container.contains(.postTimeRule) {
            postTimeRule = try container.gsonString(forKey: .postTimeRule)
        }
        if container.contains(.reviewQuoteUrl) {
            reviewQuoteUrl = try container.gsonString(forKey: .reviewQuoteUrl)
        }
        if container.contains(.voteUpUrl) {
            voteUpUrl = try container.gsonString(forKey: .voteUpUrl)
        }
        if container.contains(.voteDownUrl) {
            voteDownUrl = try container.gsonString(forKey: .voteDownUrl)
        }
        if container.contains(.postReviewUrl) {
            postReviewUrl = try container.gsonString(forKey: .postReviewUrl)
        }
        if container.contains(.postQuoteUrl) {
            postQuoteUrl = try container.gsonString(forKey: .postQuoteUrl)
        }
        if container.contains(.deleteUrl) {
            deleteUrl = try container.gsonString(forKey: .deleteUrl)
        }
        enabled = try container.gsonBool(forKey: .enabled) ?? enabled
        if container.contains(.reviewSummaryUrl) {
            reviewSummaryUrl = try container.gsonString(forKey: .reviewSummaryUrl)
        }
        if container.contains(.summaryListRule) {
            summaryListRule = try container.gsonString(forKey: .summaryListRule)
        }
        if container.contains(.summaryParagraphIndexRule) {
            summaryParagraphIndexRule = try container.gsonString(forKey: .summaryParagraphIndexRule)
        }
        if container.contains(.summaryParagraphDataRule) {
            summaryParagraphDataRule = try container.gsonString(forKey: .summaryParagraphDataRule)
        }
        if container.contains(.summaryCountRule) {
            summaryCountRule = try container.gsonString(forKey: .summaryCountRule)
        }
        if container.contains(.reviewDetailUrl) {
            reviewDetailUrl = try container.gsonString(forKey: .reviewDetailUrl)
        }
        if container.contains(.reviewDetailNextPageUrl) {
            reviewDetailNextPageUrl = try container.gsonString(forKey: .reviewDetailNextPageUrl)
        }
        if container.contains(.detailListRule) {
            detailListRule = try container.gsonString(forKey: .detailListRule)
        }
        if container.contains(.detailIdRule) {
            detailIdRule = try container.gsonString(forKey: .detailIdRule)
        }
        if container.contains(.detailAvatarRule) {
            detailAvatarRule = try container.gsonString(forKey: .detailAvatarRule)
        }
        if container.contains(.detailNameRule) {
            detailNameRule = try container.gsonString(forKey: .detailNameRule)
        }
        if container.contains(.detailBadgeRule) {
            detailBadgeRule = try container.gsonString(forKey: .detailBadgeRule)
        }
        if container.contains(.detailContentRule) {
            detailContentRule = try container.gsonString(forKey: .detailContentRule)
        }
        if container.contains(.replyListRule) {
            replyListRule = try container.gsonString(forKey: .replyListRule)
        }
        if container.contains(.replyIdRule) {
            replyIdRule = try container.gsonString(forKey: .replyIdRule)
        }
        if container.contains(.replyAvatarRule) {
            replyAvatarRule = try container.gsonString(forKey: .replyAvatarRule)
        }
        if container.contains(.replyNameRule) {
            replyNameRule = try container.gsonString(forKey: .replyNameRule)
        }
        if container.contains(.replyBadgeRule) {
            replyBadgeRule = try container.gsonString(forKey: .replyBadgeRule)
        }
        if container.contains(.replyContentRule) {
            replyContentRule = try container.gsonString(forKey: .replyContentRule)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reviewUrl, forKey: .reviewUrl)
        try container.encode(avatarRule, forKey: .avatarRule)
        try container.encode(contentRule, forKey: .contentRule)
        try container.encode(postTimeRule, forKey: .postTimeRule)
        try container.encode(reviewQuoteUrl, forKey: .reviewQuoteUrl)
        try container.encode(voteUpUrl, forKey: .voteUpUrl)
        try container.encode(voteDownUrl, forKey: .voteDownUrl)
        try container.encode(postReviewUrl, forKey: .postReviewUrl)
        try container.encode(postQuoteUrl, forKey: .postQuoteUrl)
        try container.encode(deleteUrl, forKey: .deleteUrl)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(reviewSummaryUrl, forKey: .reviewSummaryUrl)
        try container.encode(summaryListRule, forKey: .summaryListRule)
        try container.encode(summaryParagraphIndexRule, forKey: .summaryParagraphIndexRule)
        try container.encode(summaryParagraphDataRule, forKey: .summaryParagraphDataRule)
        try container.encode(summaryCountRule, forKey: .summaryCountRule)
        try container.encode(reviewDetailUrl, forKey: .reviewDetailUrl)
        try container.encode(reviewDetailNextPageUrl, forKey: .reviewDetailNextPageUrl)
        try container.encode(detailListRule, forKey: .detailListRule)
        try container.encode(detailIdRule, forKey: .detailIdRule)
        try container.encode(detailAvatarRule, forKey: .detailAvatarRule)
        try container.encode(detailNameRule, forKey: .detailNameRule)
        try container.encode(detailBadgeRule, forKey: .detailBadgeRule)
        try container.encode(detailContentRule, forKey: .detailContentRule)
        try container.encode(replyListRule, forKey: .replyListRule)
        try container.encode(replyIdRule, forKey: .replyIdRule)
        try container.encode(replyAvatarRule, forKey: .replyAvatarRule)
        try container.encode(replyNameRule, forKey: .replyNameRule)
        try container.encode(replyBadgeRule, forKey: .replyBadgeRule)
        try container.encode(replyContentRule, forKey: .replyContentRule)
    }

}
