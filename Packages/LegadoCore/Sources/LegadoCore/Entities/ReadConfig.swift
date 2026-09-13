import Foundation

/// Kotlin cb664b84d: Book.kt:500，阅读设置的全部持久化字段。
public struct ReadConfig: Codable, Equatable {
    /// Kotlin 默认值：`false`（Book.kt:501）。
    public var reverseToc: Bool = false
    /// Kotlin 默认值：`false`（Book.kt:502）。
    public var reverseTocDisplay: Bool = false
    /// Kotlin 默认值：`true`（Book.kt:503）。
    public var tocExpanded: Bool = true
    /// Kotlin 默认值：`null`（Book.kt:504）。
    public var pageAnim: Int? = nil
    /// Kotlin 默认值：`false`（Book.kt:505）。
    public var reSegment: Bool = false
    /// Kotlin 默认值：`null`（Book.kt:506）。
    public var imageStyle: String? = nil
    /// Kotlin 默认值：`null`（Book.kt:507）。
    public var useReplaceRule: Bool? = nil
    /// Kotlin 默认值：`0L`（Book.kt:508）。
    public var delTag: Int64 = 0
    /// Kotlin 默认值：`null`（Book.kt:509）。
    public var ttsEngine: String? = nil
    /// Kotlin 默认值：`true`（Book.kt:510）。
    public var splitLongChapter: Bool = true
    /// Kotlin 默认值：`false`（Book.kt:511）。
    public var readSimulating: Bool = false
    /// Kotlin 默认值：`null`（Book.kt:512）。
    public var startDate: KotlinLocalDate? = nil
    /// Kotlin 默认值：`null`（Book.kt:513）。
    public var startChapter: Int? = nil
    /// Kotlin 默认值：`3`（Book.kt:514）。
    public var dailyChapters: Int = 3
    /// Kotlin 默认值：`0`（Book.kt:515）。
    public var openCredits: Int = 0
    /// Kotlin 默认值：`0`（Book.kt:516）。
    public var closeCredits: Int = 0
    /// Kotlin 默认值：`0`（Book.kt:517）。
    public var playMode: Int = 0
    /// Kotlin 默认值：`1.0f`（Book.kt:518）。
    public var playSpeed: Float = 1.0
    /// Kotlin 默认值：`false`（Book.kt:519）。
    public var useGlobalAudioSkip: Bool = false
    /// Kotlin 默认值：`emptyList()`（Book.kt:521）。
    public var manualReplaceRuleIds: [Int64?]? = []

    private enum CodingKeys: String, CodingKey {
        case reverseToc
        case reverseTocDisplay
        case tocExpanded
        case pageAnim
        case reSegment
        case imageStyle
        case useReplaceRule
        case delTag
        case ttsEngine
        case splitLongChapter
        case readSimulating
        case startDate
        case startChapter
        case dailyChapters
        case openCredits
        case closeCredits
        case playMode
        case playSpeed
        case useGlobalAudioSkip
        case manualReplaceRuleIds
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reverseToc = try container.gsonBool(forKey: .reverseToc) ?? reverseToc
        reverseTocDisplay = try container.gsonBool(forKey: .reverseTocDisplay) ?? reverseTocDisplay
        tocExpanded = try container.gsonBool(forKey: .tocExpanded) ?? tocExpanded
        if container.contains(.pageAnim) {
            pageAnim = try container.gsonBoxedInt(forKey: .pageAnim)
        }
        reSegment = try container.gsonBool(forKey: .reSegment) ?? reSegment
        if container.contains(.imageStyle) {
            imageStyle = try container.gsonString(forKey: .imageStyle)
        }
        if container.contains(.useReplaceRule) {
            useReplaceRule = try container.gsonBool(forKey: .useReplaceRule)
        }
        delTag = try container.gsonLong(forKey: .delTag) ?? delTag
        if container.contains(.ttsEngine) {
            ttsEngine = try container.gsonString(forKey: .ttsEngine)
        }
        splitLongChapter = try container.gsonBool(forKey: .splitLongChapter) ?? splitLongChapter
        readSimulating = try container.gsonBool(forKey: .readSimulating) ?? readSimulating
        if container.contains(.startDate) {
            startDate = try container.decodeIfPresent(GsonValue.self, forKey: .startDate).flatMap(KotlinLocalDate.parse)
        }
        if container.contains(.startChapter) {
            startChapter = try container.gsonBoxedInt(forKey: .startChapter)
        }
        dailyChapters = try container.gsonInt(forKey: .dailyChapters) ?? dailyChapters
        openCredits = try container.gsonInt(forKey: .openCredits) ?? openCredits
        closeCredits = try container.gsonInt(forKey: .closeCredits) ?? closeCredits
        playMode = try container.gsonInt(forKey: .playMode) ?? playMode
        playSpeed = try container.gsonFloat(forKey: .playSpeed) ?? playSpeed
        useGlobalAudioSkip = try container.gsonBool(forKey: .useGlobalAudioSkip) ?? useGlobalAudioSkip
        if container.contains(.manualReplaceRuleIds) {
            manualReplaceRuleIds = try container.gsonLongList(forKey: .manualReplaceRuleIds)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reverseToc, forKey: .reverseToc)
        try container.encode(reverseTocDisplay, forKey: .reverseTocDisplay)
        try container.encode(tocExpanded, forKey: .tocExpanded)
        try container.encode(pageAnim, forKey: .pageAnim)
        try container.encode(reSegment, forKey: .reSegment)
        try container.encode(imageStyle, forKey: .imageStyle)
        try container.encode(useReplaceRule, forKey: .useReplaceRule)
        try container.encode(delTag, forKey: .delTag)
        try container.encode(ttsEngine, forKey: .ttsEngine)
        try container.encode(splitLongChapter, forKey: .splitLongChapter)
        try container.encode(readSimulating, forKey: .readSimulating)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(startChapter, forKey: .startChapter)
        try container.encode(dailyChapters, forKey: .dailyChapters)
        try container.encode(openCredits, forKey: .openCredits)
        try container.encode(closeCredits, forKey: .closeCredits)
        try container.encode(playMode, forKey: .playMode)
        try container.encode(playSpeed, forKey: .playSpeed)
        try container.encode(useGlobalAudioSkip, forKey: .useGlobalAudioSkip)
        try container.encode(manualReplaceRuleIds, forKey: .manualReplaceRuleIds)
    }
}
