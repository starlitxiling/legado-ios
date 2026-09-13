import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/BookGroup.kt.
public struct BookGroup: Codable, Equatable {
    /// Kotlin 默认值：`0b1`（BookGroup.kt:17）。
    public var groupId: Int64 = 1
    /// Kotlin 默认值：`""`（BookGroup.kt:18）。
    public var groupName: String? = ""
    /// Kotlin 默认值：`null`（BookGroup.kt:19）。
    public var cover: String? = nil
    /// Kotlin 默认值：`0`（BookGroup.kt:20）。
    public var order: Int = 0
    /// Kotlin 默认值：`true`（BookGroup.kt:22）。
    public var enableRefresh: Bool = true
    /// Kotlin 默认值：`true`（BookGroup.kt:24）。
    public var show: Bool = true
    /// Kotlin 默认值：`-1`（BookGroup.kt:26）。
    public var bookSort: Int = -1
    /// Kotlin 默认值：`false`（BookGroup.kt:29）。
    public var onlyUpdateRead: Bool = false

    private enum CodingKeys: String, CodingKey {
        case groupId
        case groupName
        case cover
        case order
        case enableRefresh
        case show
        case bookSort
        case onlyUpdateRead
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupId = try container.gsonLong(forKey: .groupId) ?? groupId
        if container.contains(.groupName) {
            groupName = try container.gsonString(forKey: .groupName)
        }
        if container.contains(.cover) {
            cover = try container.gsonString(forKey: .cover)
        }
        order = try container.gsonInt(forKey: .order) ?? order
        enableRefresh = try container.gsonBool(forKey: .enableRefresh) ?? enableRefresh
        show = try container.gsonBool(forKey: .show) ?? show
        bookSort = try container.gsonInt(forKey: .bookSort) ?? bookSort
        onlyUpdateRead = try container.gsonBool(forKey: .onlyUpdateRead) ?? onlyUpdateRead
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupId, forKey: .groupId)
        try container.encode(groupName, forKey: .groupName)
        try container.encode(cover, forKey: .cover)
        try container.encode(order, forKey: .order)
        try container.encode(enableRefresh, forKey: .enableRefresh)
        try container.encode(show, forKey: .show)
        try container.encode(bookSort, forKey: .bookSort)
        try container.encode(onlyUpdateRead, forKey: .onlyUpdateRead)
    }

}
