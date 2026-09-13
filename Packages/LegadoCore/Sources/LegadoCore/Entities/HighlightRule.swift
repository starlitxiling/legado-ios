import Foundation
import GRDB

public struct HighlightRule: StorageRow {
    public static let databaseTableName = "highlightRules"
    public var id: Int64 = 0
    public var uuid: String = UUID().uuidString
    public var name: String = ""
    public var pattern: String = ""
    public var isRegex: Bool = false
    public var scope: String? = nil
    public var isEnabled: Bool = true
    public var style: String = ""
    public var order: Int = Int(Int32.min)
    public var timeoutMillisecond: Int64 = 3000
    public var group: String? = nil
    public var applyToTitle: Bool = false
    public var applyToBody: Bool = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case id, uuid, name, pattern, isRegex, scope, isEnabled, style, order, timeoutMillisecond, group, applyToTitle, applyToBody
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.gsonLong(forKey: .id) ?? id
        uuid = try container.gsonString(forKey: .uuid) ?? uuid
        name = try container.gsonString(forKey: .name) ?? name
        pattern = try container.gsonString(forKey: .pattern) ?? pattern
        isRegex = try container.gsonBool(forKey: .isRegex) ?? isRegex
        if container.contains(.scope) { scope = try container.gsonString(forKey: .scope) }
        isEnabled = try container.gsonBool(forKey: .isEnabled) ?? isEnabled
        style = try container.gsonString(forKey: .style) ?? style
        order = try container.gsonInt(forKey: .order) ?? order
        timeoutMillisecond = try container.gsonLong(forKey: .timeoutMillisecond) ?? timeoutMillisecond
        if container.contains(.group) { group = try container.gsonString(forKey: .group) }
        applyToTitle = try container.gsonBool(forKey: .applyToTitle) ?? applyToTitle
        applyToBody = try container.gsonBool(forKey: .applyToBody) ?? applyToBody
    }

    public init(row: Row) {
        id = row["id"]
        uuid = row["uuid"]
        name = row["name"]
        pattern = row["pattern"]
        isRegex = row["isRegex"]
        scope = row["scope"]
        isEnabled = row["isEnabled"]
        style = row["style"]
        order = row["sortOrder"]
        timeoutMillisecond = row["timeoutMillisecond"]
        group = row["group"]
        applyToTitle = row["applyToTitle"]
        applyToBody = row["applyToBody"]
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id == 0 ? nil : id
        container["uuid"] = uuid
        container["name"] = name
        container["pattern"] = pattern
        container["isRegex"] = isRegex
        container["scope"] = scope
        container["isEnabled"] = isEnabled
        container["style"] = style
        container["sortOrder"] = order
        container["timeoutMillisecond"] = timeoutMillisecond
        container["group"] = group
        container["applyToTitle"] = applyToTitle
        container["applyToBody"] = applyToBody
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public typealias HighlightRuleRepository = Repository<HighlightRule>

