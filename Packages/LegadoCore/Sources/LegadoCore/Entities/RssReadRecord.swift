import Foundation
import GRDB

public struct RssReadRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "rssReadRecords"
    public var record: String = ""
    public var title: String? = nil
    public var readTime: Int64? = nil
    public var read: Bool = true
    public var origin: String = ""
    public var sort: String = ""
    public var image: String? = nil
    public var type: Int = 0
    public var durPos: Int = 0
    public var pubDate: String? = nil
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case record, title, readTime, read, origin, sort, image, type, durPos, pubDate
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        record = try c.gsonString(forKey: .record) ?? ""
        title = try c.gsonString(forKey: .title)
        readTime = try c.gsonLong(forKey: .readTime)
        read = try c.gsonBool(forKey: .read) ?? true
        origin = try c.gsonString(forKey: .origin) ?? ""
        sort = try c.gsonString(forKey: .sort) ?? ""
        image = try c.gsonString(forKey: .image)
        type = try c.gsonInt(forKey: .type) ?? 0
        durPos = try c.gsonInt(forKey: .durPos) ?? 0
        pubDate = try c.gsonString(forKey: .pubDate)
    }
    public init(row: Row) {
        record = row["record"]
        title = row["title"]
        readTime = row["readTime"]
        read = row["read"]
        origin = row["origin"]
        sort = row["sort"]
        image = row["image"]
        type = row["type"]
        durPos = row["durPos"]
        pubDate = row["pubDate"]
    }
}
