import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/BookSource.kt.
public struct BookSource: Codable, Equatable {
    /// Kotlin 默认值：`""`（BookSource.kt:34）。
    public var bookSourceUrl: String? = ""
    /// Kotlin 默认值：`""`（BookSource.kt:36）。
    public var bookSourceName: String? = ""
    /// Kotlin 默认值：`null`（BookSource.kt:38）。
    public var bookSourceGroup: String? = nil
    /// Kotlin 默认值：`0`（BookSource.kt:41）。
    public var bookSourceType: Int = 0
    /// Kotlin 默认值：`null`（BookSource.kt:43）。
    public var bookUrlPattern: String? = nil
    /// Kotlin 默认值：`0`（BookSource.kt:46）。
    public var customOrder: Int = 0
    /// Kotlin 默认值：`true`（BookSource.kt:49）。
    public var enabled: Bool = true
    /// Kotlin 默认值：`true`（BookSource.kt:52）。
    public var enabledExplore: Bool = true
    /// Kotlin 默认值：`null`（BookSource.kt:54）。
    public var jsLib: String? = nil
    /// Kotlin 默认值：`true`（BookSource.kt:57）。
    public var enabledCookieJar: Bool? = true
    /// Kotlin 默认值：`null`（BookSource.kt:59）。
    public var concurrentRate: String? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:61）。
    public var header: String? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:63）。
    public var loginUrl: String? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:65）。
    public var loginUi: String? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:67）。
    public var loginCheckJs: String? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:69）。
    public var coverDecodeJs: String? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:71）。
    public var bookSourceComment: String? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:73）。
    public var variableComment: String? = nil
    /// Kotlin 默认值：`0`（BookSource.kt:75）。
    public var lastUpdateTime: Int64 = 0
    /// Kotlin 默认值：`180000L`（BookSource.kt:77）。
    public var respondTime: Int64 = 180000
    /// Kotlin 默认值：`0`（BookSource.kt:79）。
    public var weight: Int = 0
    /// Kotlin 默认值：`null`（BookSource.kt:81）。
    public var exploreUrl: String? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:83）。
    public var exploreScreen: String? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:85）。
    public var ruleExplore: ExploreRule? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:87）。
    public var searchUrl: String? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:89）。
    public var ruleSearch: SearchRule? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:91）。
    public var ruleBookInfo: BookInfoRule? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:93）。
    public var ruleToc: TocRule? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:95）。
    public var ruleContent: ContentRule? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:97）。
    public var ruleReview: ReviewRule? = nil
    /// Kotlin 默认值：`null`（BookSource.kt:99）。
    public var mainJs: String? = nil
    /// Kotlin 默认值：`false`（BookSource.kt:101）。
    public var eventListener: Bool = false
    /// Kotlin 默认值：`false`（BookSource.kt:103）。
    public var customButton: Bool = false

    private enum CodingKeys: String, CodingKey {
        case bookSourceUrl
        case bookSourceName
        case bookSourceGroup
        case bookSourceType
        case bookUrlPattern
        case customOrder
        case enabled
        case enabledExplore
        case jsLib
        case enabledCookieJar
        case concurrentRate
        case header
        case loginUrl
        case loginUi
        case loginCheckJs
        case coverDecodeJs
        case bookSourceComment
        case variableComment
        case lastUpdateTime
        case respondTime
        case weight
        case exploreUrl
        case exploreScreen
        case ruleExplore
        case searchUrl
        case ruleSearch
        case ruleBookInfo
        case ruleToc
        case ruleContent
        case ruleReview
        case mainJs
        case eventListener
        case customButton
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.bookSourceUrl) {
            bookSourceUrl = try container.gsonString(forKey: .bookSourceUrl)
        }
        if container.contains(.bookSourceName) {
            bookSourceName = try container.gsonString(forKey: .bookSourceName)
        }
        if container.contains(.bookSourceGroup) {
            bookSourceGroup = try container.gsonString(forKey: .bookSourceGroup)
        }
        bookSourceType = try container.gsonInt(forKey: .bookSourceType) ?? bookSourceType
        if container.contains(.bookUrlPattern) {
            bookUrlPattern = try container.gsonString(forKey: .bookUrlPattern)
        }
        customOrder = try container.gsonInt(forKey: .customOrder) ?? customOrder
        enabled = try container.gsonBool(forKey: .enabled) ?? enabled
        enabledExplore = try container.gsonBool(forKey: .enabledExplore) ?? enabledExplore
        if container.contains(.jsLib) {
            jsLib = try container.gsonString(forKey: .jsLib)
        }
        if container.contains(.enabledCookieJar) {
            enabledCookieJar = try container.gsonBool(forKey: .enabledCookieJar)
        }
        if container.contains(.concurrentRate) {
            concurrentRate = try container.gsonString(forKey: .concurrentRate)
        }
        if container.contains(.header) {
            header = try container.gsonString(forKey: .header)
        }
        if container.contains(.loginUrl) {
            loginUrl = try container.gsonString(forKey: .loginUrl)
        }
        if container.contains(.loginUi) {
            loginUi = try container.gsonString(forKey: .loginUi)
        }
        if container.contains(.loginCheckJs) {
            loginCheckJs = try container.gsonString(forKey: .loginCheckJs)
        }
        if container.contains(.coverDecodeJs) {
            coverDecodeJs = try container.gsonString(forKey: .coverDecodeJs)
        }
        if container.contains(.bookSourceComment) {
            bookSourceComment = try container.gsonString(forKey: .bookSourceComment)
        }
        if container.contains(.variableComment) {
            variableComment = try container.gsonString(forKey: .variableComment)
        }
        lastUpdateTime = try container.gsonLong(forKey: .lastUpdateTime) ?? lastUpdateTime
        respondTime = try container.gsonLong(forKey: .respondTime) ?? respondTime
        weight = try container.gsonInt(forKey: .weight) ?? weight
        if container.contains(.exploreUrl) {
            exploreUrl = try container.gsonString(forKey: .exploreUrl)
        }
        if container.contains(.exploreScreen) {
            exploreScreen = try container.gsonString(forKey: .exploreScreen)
        }
        ruleExplore = try container.gsonRule(ExploreRule.self, forKey: .ruleExplore)
        if container.contains(.searchUrl) {
            searchUrl = try container.gsonString(forKey: .searchUrl)
        }
        ruleSearch = try container.gsonRule(SearchRule.self, forKey: .ruleSearch)
        ruleBookInfo = try container.gsonRule(BookInfoRule.self, forKey: .ruleBookInfo)
        ruleToc = try container.gsonRule(TocRule.self, forKey: .ruleToc)
        ruleContent = try container.gsonRule(ContentRule.self, forKey: .ruleContent)
        ruleReview = try container.gsonRule(ReviewRule.self, forKey: .ruleReview)
        if container.contains(.mainJs) {
            mainJs = try container.gsonString(forKey: .mainJs)
        }
        eventListener = try container.gsonBool(forKey: .eventListener) ?? eventListener
        customButton = try container.gsonBool(forKey: .customButton) ?? customButton
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bookSourceUrl, forKey: .bookSourceUrl)
        try container.encode(bookSourceName, forKey: .bookSourceName)
        try container.encode(bookSourceGroup, forKey: .bookSourceGroup)
        try container.encode(bookSourceType, forKey: .bookSourceType)
        try container.encode(bookUrlPattern, forKey: .bookUrlPattern)
        try container.encode(customOrder, forKey: .customOrder)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(enabledExplore, forKey: .enabledExplore)
        try container.encode(jsLib, forKey: .jsLib)
        try container.encode(enabledCookieJar, forKey: .enabledCookieJar)
        try container.encode(concurrentRate, forKey: .concurrentRate)
        try container.encode(header, forKey: .header)
        try container.encode(loginUrl, forKey: .loginUrl)
        try container.encode(loginUi, forKey: .loginUi)
        try container.encode(loginCheckJs, forKey: .loginCheckJs)
        try container.encode(coverDecodeJs, forKey: .coverDecodeJs)
        try container.encode(bookSourceComment, forKey: .bookSourceComment)
        try container.encode(variableComment, forKey: .variableComment)
        try container.encode(lastUpdateTime, forKey: .lastUpdateTime)
        try container.encode(respondTime, forKey: .respondTime)
        try container.encode(weight, forKey: .weight)
        try container.encode(exploreUrl, forKey: .exploreUrl)
        try container.encode(exploreScreen, forKey: .exploreScreen)
        try container.encode(ruleExplore, forKey: .ruleExplore)
        try container.encode(searchUrl, forKey: .searchUrl)
        try container.encode(ruleSearch, forKey: .ruleSearch)
        try container.encode(ruleBookInfo, forKey: .ruleBookInfo)
        try container.encode(ruleToc, forKey: .ruleToc)
        try container.encode(ruleContent, forKey: .ruleContent)
        try container.encode(ruleReview, forKey: .ruleReview)
        try container.encode(mainJs, forKey: .mainJs)
        try container.encode(eventListener, forKey: .eventListener)
        try container.encode(customButton, forKey: .customButton)
    }

}
