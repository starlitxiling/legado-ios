import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/Book.kt.
public struct Book: Codable, Equatable {
    /// Kotlin 默认值：`""`（Book.kt:43）。
    public var bookUrl: String? = ""
    /// Kotlin 默认值：`""`（Book.kt:46）。
    public var tocUrl: String? = ""
    /// Kotlin 默认值：`BookType.localTag`（Book.kt:49）。
    public var origin: String? = "loc_book"
    /// Kotlin 默认值：`""`（Book.kt:52）。
    public var originName: String? = ""
    /// Kotlin 默认值：`""`（Book.kt:55）。
    public var name: String? = ""
    /// Kotlin 默认值：`""`（Book.kt:58）。
    public var author: String? = ""
    /// Kotlin 默认值：`null`（Book.kt:60）。
    public var kind: String? = nil
    /// Kotlin 默认值：`null`（Book.kt:62）。
    public var customTag: String? = nil
    /// Kotlin 默认值：`null`（Book.kt:64）。
    public var coverUrl: String? = nil
    /// Kotlin 默认值：`null`（Book.kt:66）。
    public var customCoverUrl: String? = nil
    /// Kotlin 默认值：`null`（Book.kt:68）。
    public var intro: String? = nil
    /// Kotlin 默认值：`null`（Book.kt:70）。
    public var customIntro: String? = nil
    /// Kotlin 默认值：`null`（Book.kt:72）。
    public var charset: String? = nil
    /// Kotlin 默认值：`BookType.text`（Book.kt:75）。
    public var type: Int = 8
    /// Kotlin 默认值：`0`（Book.kt:78）。
    public var group: Int64 = 0
    /// Kotlin 默认值：`null`（Book.kt:80）。
    public var latestChapterTitle: String? = nil
    /// Kotlin 默认值：`System.currentTimeMillis()`（Book.kt:83）。
    public var latestChapterTime: Int64
    /// Kotlin 默认值：`System.currentTimeMillis()`（Book.kt:86）。
    public var lastCheckTime: Int64
    /// Kotlin 默认值：`0`（Book.kt:89）。
    public var lastCheckCount: Int = 0
    /// Kotlin 默认值：`0`（Book.kt:92）。
    public var totalChapterNum: Int = 0
    /// Kotlin 默认值：`null`（Book.kt:94）。
    public var durChapterTitle: String? = nil
    /// Kotlin 默认值：`0`（Book.kt:97）。
    public var durChapterIndex: Int = 0
    /// Kotlin 默认值：`0`（Book.kt:100）。
    public var durVolumeIndex: Int = 0
    /// Kotlin 默认值：`0`（Book.kt:103）。
    public var chapterInVolumeIndex: Int = 0
    /// Kotlin 默认值：`0`（Book.kt:106）。
    public var durChapterPos: Int = 0
    /// Kotlin 默认值：`System.currentTimeMillis()`（Book.kt:109）。
    public var durChapterTime: Int64
    /// Kotlin 默认值：`null`（Book.kt:111）。
    public var wordCount: String? = nil
    /// Kotlin 默认值：`true`（Book.kt:114）。
    public var canUpdate: Bool = true
    /// Kotlin 默认值：`0`（Book.kt:117）。
    public var order: Int = 0
    /// Kotlin 默认值：`0`（Book.kt:120）。
    public var originOrder: Int = 0
    /// Kotlin 默认值：`null`（Book.kt:122）。
    public var variable: String? = nil
    /// Kotlin 默认值：`null`（Book.kt:124）。
    public var readConfig: ReadConfig? = nil
    /// Kotlin 默认值：`0L`（Book.kt:127）。
    public var syncTime: Int64 = 0
    /// Kotlin 默认值：`null`（Book.kt:129）。
    public var persistedCoverUrl: String? = nil

    private enum CodingKeys: String, CodingKey {
        case bookUrl
        case tocUrl
        case origin
        case originName
        case name
        case author
        case kind
        case customTag
        case coverUrl
        case customCoverUrl
        case intro
        case customIntro
        case charset
        case type
        case group
        case latestChapterTitle
        case latestChapterTime
        case lastCheckTime
        case lastCheckCount
        case totalChapterNum
        case durChapterTitle
        case durChapterIndex
        case durVolumeIndex
        case chapterInVolumeIndex
        case durChapterPos
        case durChapterTime
        case wordCount
        case canUpdate
        case order
        case originOrder
        case variable
        case readConfig
        case syncTime
        case persistedCoverUrl
    }

    public init(now: Int64 = GsonDecoding.currentTimeMillis()) {
        latestChapterTime = now
        lastCheckTime = now
        durChapterTime = now
    }

    public init(from decoder: Decoder) throws {
        self.init(now: GsonDecoding.time(from: decoder))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.bookUrl) {
            bookUrl = try container.gsonString(forKey: .bookUrl)
        }
        if container.contains(.tocUrl) {
            tocUrl = try container.gsonString(forKey: .tocUrl)
        }
        if container.contains(.origin) {
            origin = try container.gsonString(forKey: .origin)
        }
        if container.contains(.originName) {
            originName = try container.gsonString(forKey: .originName)
        }
        if container.contains(.name) {
            name = try container.gsonString(forKey: .name)
        }
        if container.contains(.author) {
            author = try container.gsonString(forKey: .author)
        }
        if container.contains(.kind) {
            kind = try container.gsonString(forKey: .kind)
        }
        if container.contains(.customTag) {
            customTag = try container.gsonString(forKey: .customTag)
        }
        if container.contains(.coverUrl) {
            coverUrl = try container.gsonString(forKey: .coverUrl)
        }
        if container.contains(.customCoverUrl) {
            customCoverUrl = try container.gsonString(forKey: .customCoverUrl)
        }
        if container.contains(.intro) {
            intro = try container.gsonString(forKey: .intro)
        }
        if container.contains(.customIntro) {
            customIntro = try container.gsonString(forKey: .customIntro)
        }
        if container.contains(.charset) {
            charset = try container.gsonString(forKey: .charset)
        }
        type = try container.gsonInt(forKey: .type) ?? type
        group = try container.gsonLong(forKey: .group) ?? group
        if container.contains(.latestChapterTitle) {
            latestChapterTitle = try container.gsonString(forKey: .latestChapterTitle)
        }
        latestChapterTime = try container.gsonLong(forKey: .latestChapterTime) ?? latestChapterTime
        lastCheckTime = try container.gsonLong(forKey: .lastCheckTime) ?? lastCheckTime
        lastCheckCount = try container.gsonInt(forKey: .lastCheckCount) ?? lastCheckCount
        totalChapterNum = try container.gsonInt(forKey: .totalChapterNum) ?? totalChapterNum
        if container.contains(.durChapterTitle) {
            durChapterTitle = try container.gsonString(forKey: .durChapterTitle)
        }
        durChapterIndex = try container.gsonInt(forKey: .durChapterIndex) ?? durChapterIndex
        durVolumeIndex = try container.gsonInt(forKey: .durVolumeIndex) ?? durVolumeIndex
        chapterInVolumeIndex = try container.gsonInt(forKey: .chapterInVolumeIndex) ?? chapterInVolumeIndex
        durChapterPos = try container.gsonInt(forKey: .durChapterPos) ?? durChapterPos
        durChapterTime = try container.gsonLong(forKey: .durChapterTime) ?? durChapterTime
        if container.contains(.wordCount) {
            wordCount = try container.gsonString(forKey: .wordCount)
        }
        canUpdate = try container.gsonBool(forKey: .canUpdate) ?? canUpdate
        order = try container.gsonInt(forKey: .order) ?? order
        originOrder = try container.gsonInt(forKey: .originOrder) ?? originOrder
        if container.contains(.variable) {
            variable = try container.gsonString(forKey: .variable)
        }
        readConfig = try container.decodeIfPresent(ReadConfig.self, forKey: .readConfig)
        syncTime = try container.gsonLong(forKey: .syncTime) ?? syncTime
        if container.contains(.persistedCoverUrl) {
            persistedCoverUrl = try container.gsonString(forKey: .persistedCoverUrl)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bookUrl, forKey: .bookUrl)
        try container.encode(tocUrl, forKey: .tocUrl)
        try container.encode(origin, forKey: .origin)
        try container.encode(originName, forKey: .originName)
        try container.encode(name, forKey: .name)
        try container.encode(author, forKey: .author)
        try container.encode(kind, forKey: .kind)
        try container.encode(customTag, forKey: .customTag)
        try container.encode(coverUrl, forKey: .coverUrl)
        try container.encode(customCoverUrl, forKey: .customCoverUrl)
        try container.encode(intro, forKey: .intro)
        try container.encode(customIntro, forKey: .customIntro)
        try container.encode(charset, forKey: .charset)
        try container.encode(type, forKey: .type)
        try container.encode(group, forKey: .group)
        try container.encode(latestChapterTitle, forKey: .latestChapterTitle)
        try container.encode(latestChapterTime, forKey: .latestChapterTime)
        try container.encode(lastCheckTime, forKey: .lastCheckTime)
        try container.encode(lastCheckCount, forKey: .lastCheckCount)
        try container.encode(totalChapterNum, forKey: .totalChapterNum)
        try container.encode(durChapterTitle, forKey: .durChapterTitle)
        try container.encode(durChapterIndex, forKey: .durChapterIndex)
        try container.encode(durVolumeIndex, forKey: .durVolumeIndex)
        try container.encode(chapterInVolumeIndex, forKey: .chapterInVolumeIndex)
        try container.encode(durChapterPos, forKey: .durChapterPos)
        try container.encode(durChapterTime, forKey: .durChapterTime)
        try container.encode(wordCount, forKey: .wordCount)
        try container.encode(canUpdate, forKey: .canUpdate)
        try container.encode(order, forKey: .order)
        try container.encode(originOrder, forKey: .originOrder)
        try container.encode(variable, forKey: .variable)
        try container.encode(readConfig, forKey: .readConfig)
        try container.encode(syncTime, forKey: .syncTime)
        try container.encode(persistedCoverUrl, forKey: .persistedCoverUrl)
    }

}
