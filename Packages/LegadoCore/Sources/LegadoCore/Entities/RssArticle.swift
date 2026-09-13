import Foundation
import GRDB

public struct RssArticle: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "rssArticles"
    public var origin: String = ""
    public var sort: String = ""
    public var title: String = ""
    public var order: Int64 = 0
    public var link: String = ""
    public var pubDate: String? = nil
    public var description: String? = nil
    public var content: String? = nil
    public var image: String? = nil
    public var group: String = "默认分组"
    public var read: Bool = false
    public var variable: String? = nil
    public var type: Int = 0
    public var durPos: Int = 0
    public init(origin: String = "", link: String = "", title: String = "") { self.origin = origin; self.link = link; self.title = title }
    private enum CodingKeys: String, CodingKey {
        case origin, sort, title, order, link, pubDate, description, content, image, group, read, variable, type, durPos
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        origin = try c.gsonString(forKey: .origin) ?? ""
        sort = try c.gsonString(forKey: .sort) ?? ""
        title = try c.gsonString(forKey: .title) ?? ""
        order = try c.gsonLong(forKey: .order) ?? 0
        link = try c.gsonString(forKey: .link) ?? ""
        pubDate = try c.gsonString(forKey: .pubDate)
        description = try c.gsonString(forKey: .description)
        content = try c.gsonString(forKey: .content)
        image = try c.gsonString(forKey: .image)
        group = try c.gsonString(forKey: .group) ?? "默认分组"
        read = try c.gsonBool(forKey: .read) ?? false
        variable = try c.gsonString(forKey: .variable)
        type = try c.gsonInt(forKey: .type) ?? 0
        durPos = try c.gsonInt(forKey: .durPos) ?? 0
    }
    public init(row: Row) {
        origin = row["origin"]
        sort = row["sort"]
        title = row["title"]
        order = row["order"]
        link = row["link"]
        pubDate = row["pubDate"]
        description = row["description"]
        content = row["content"]
        image = row["image"]
        group = row["group"]
        read = row["read"]
        variable = row["variable"]
        type = row["type"]
        durPos = row["durPos"]
    }
}

public extension RssArticle {
    var identity: [String] { [origin, link, sort] }
    func star(time: Int64) throws -> RssStar {
        var value = try JSONDecoder().decode(RssStar.self, from: JSONEncoder().encode(self))
        value.starTime = time
        return value
    }
}
