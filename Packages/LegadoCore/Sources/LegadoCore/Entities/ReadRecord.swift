import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/ReadRecord.kt.
public struct ReadRecord: Codable, Equatable {
    /// Kotlin 默认值：`""`（ReadRecord.kt:23）。
    public var deviceId: String? = ""
    /// Kotlin 默认值：`""`（ReadRecord.kt:24）。
    public var bookName: String? = ""
    /// Kotlin 默认值：`""`（ReadRecord.kt:29）。
    public var author: String? = ""
    /// Kotlin 默认值：`0L`（ReadRecord.kt:31）。
    public var readTime: Int64 = 0
    /// Kotlin 默认值：`System.currentTimeMillis()`（ReadRecord.kt:33）。
    public var lastRead: Int64
    /// Kotlin 默认值：`null`（ReadRecord.kt:35）。
    public var lastChapterTitle: String? = nil
    /// Kotlin 默认值：`-1`（ReadRecord.kt:37）。
    public var lastChapterIndex: Int = -1
    /// Kotlin 默认值：`0`（ReadRecord.kt:39）。
    public var lastChapterPos: Int = 0
    /// Kotlin 默认值：`null`（ReadRecord.kt:40）。
    public var coverUrl: String? = nil
    /// Kotlin 默认值：`null`（ReadRecord.kt:42）。
    public var resolvedAuthor: String? = nil

    private enum CodingKeys: String, CodingKey {
        case deviceId
        case bookName
        case author
        case readTime
        case lastRead
        case lastChapterTitle
        case lastChapterIndex
        case lastChapterPos
        case coverUrl
        case resolvedAuthor
    }

    public init(now: Int64 = GsonDecoding.currentTimeMillis()) {
        lastRead = now
    }

    public init(from decoder: Decoder) throws {
        self.init(now: GsonDecoding.time(from: decoder))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.deviceId) {
            deviceId = try container.gsonString(forKey: .deviceId)
        }
        if container.contains(.bookName) {
            bookName = try container.gsonString(forKey: .bookName)
        }
        if container.contains(.author) {
            author = try container.gsonString(forKey: .author)
        }
        readTime = try container.gsonLong(forKey: .readTime) ?? readTime
        lastRead = try container.gsonLong(forKey: .lastRead) ?? lastRead
        if container.contains(.lastChapterTitle) {
            lastChapterTitle = try container.gsonString(forKey: .lastChapterTitle)
        }
        lastChapterIndex = try container.gsonInt(forKey: .lastChapterIndex) ?? lastChapterIndex
        lastChapterPos = try container.gsonInt(forKey: .lastChapterPos) ?? lastChapterPos
        if container.contains(.coverUrl) {
            coverUrl = try container.gsonString(forKey: .coverUrl)
        }
        if container.contains(.resolvedAuthor) {
            resolvedAuthor = try container.gsonString(forKey: .resolvedAuthor)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(bookName, forKey: .bookName)
        try container.encode(author, forKey: .author)
        try container.encode(readTime, forKey: .readTime)
        try container.encode(lastRead, forKey: .lastRead)
        try container.encode(lastChapterTitle, forKey: .lastChapterTitle)
        try container.encode(lastChapterIndex, forKey: .lastChapterIndex)
        try container.encode(lastChapterPos, forKey: .lastChapterPos)
        try container.encode(coverUrl, forKey: .coverUrl)
        try container.encode(resolvedAuthor, forKey: .resolvedAuthor)
    }

}
