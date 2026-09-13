import GRDB

/// Kotlin cb664b84d: data/entities/BookSource.kt。
public struct BookSourceRow: StorageRow {
    public static let databaseTableName = "book_sources"
    public var `bookSourceUrl`: String = ""
    public var `bookSourceName`: String = ""
    public var `bookSourceGroup`: String? = nil
    public var `bookSourceType`: Int = 0
    public var `bookUrlPattern`: String? = nil
    public var `customOrder`: Int = 0
    public var `enabled`: Bool = true
    public var `enabledExplore`: Bool = true
    public var `jsLib`: String? = nil
    public var `enabledCookieJar`: Bool? = true
    public var `concurrentRate`: String? = nil
    public var `header`: String? = nil
    public var `loginUrl`: String? = nil
    public var `loginUi`: String? = nil
    public var `loginCheckJs`: String? = nil
    public var `coverDecodeJs`: String? = nil
    public var `bookSourceComment`: String? = nil
    public var `variableComment`: String? = nil
    public var `lastUpdateTime`: Int64 = 0
    public var `respondTime`: Int64 = 180000
    public var `weight`: Int = 0
    public var `exploreUrl`: String? = nil
    public var `exploreScreen`: String? = nil
    /// Room TypeConverter 的 JSON 文本。
    public var `ruleExplore`: String? = nil
    public var `searchUrl`: String? = nil
    /// Room TypeConverter 的 JSON 文本。
    public var `ruleSearch`: String? = nil
    /// Room TypeConverter 的 JSON 文本。
    public var `ruleBookInfo`: String? = nil
    /// Room TypeConverter 的 JSON 文本。
    public var `ruleToc`: String? = nil
    /// Room TypeConverter 的 JSON 文本。
    public var `ruleContent`: String? = nil
    /// Room TypeConverter 的 JSON 文本。
    public var `ruleReview`: String? = nil
    public var `mainJs`: String? = nil
    public var `eventListener`: Bool = false
    public var `customButton`: Bool = false

    public init() {}
}
