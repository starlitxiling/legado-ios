import Foundation
import GRDB

public struct RuleSub: StorageRow {
    public static let databaseTableName = "ruleSubs"
    public var id: Int64 = 0
    public var name: String = ""
    public var url: String = ""
    public var type: Int = 0
    public var customOrder: Int = 0
    public var autoUpdate: Bool = false
    public var update: Int64 = 0
    public var updateInterval: Int = 0
    public var silentUpdate: Bool = false
    public var js: String? = nil
    public var showRule: String? = nil
    public var sourceUrl: String? = nil

    public init() {}

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id == 0 ? nil : id
        container["name"] = name
        container["url"] = url
        container["type"] = type
        container["customOrder"] = customOrder
        container["autoUpdate"] = autoUpdate
        container["update"] = update
        container["updateInterval"] = updateInterval
        container["silentUpdate"] = silentUpdate
        container["js"] = js
        container["showRule"] = showRule
        container["sourceUrl"] = sourceUrl
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public init(row: Row) {
        id = row["id"]
        name = row["name"]
        url = row["url"]
        type = row["type"]
        customOrder = row["customOrder"]
        autoUpdate = row["autoUpdate"]
        update = row["update"]
        updateInterval = row["updateInterval"]
        silentUpdate = row["silentUpdate"]
        js = row["js"]
        showRule = row["showRule"]
        sourceUrl = row["sourceUrl"]
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, url, type, customOrder, autoUpdate, update, updateInterval, silentUpdate, js, showRule, sourceUrl
    }

    public init(from decoder: Decoder) throws {
        self.init()
        update = GsonDecoding.time(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.gsonLong(forKey: .id) ?? GsonDecoding.subscriptionID(from: decoder)
        name = try container.gsonString(forKey: .name) ?? name
        url = try container.gsonString(forKey: .url) ?? url
        type = try container.gsonInt(forKey: .type) ?? type
        customOrder = try container.gsonInt(forKey: .customOrder) ?? customOrder
        autoUpdate = try container.gsonBool(forKey: .autoUpdate) ?? autoUpdate
        update = try container.gsonLong(forKey: .update) ?? update
        updateInterval = try container.gsonInt(forKey: .updateInterval) ?? updateInterval
        silentUpdate = try container.gsonBool(forKey: .silentUpdate) ?? silentUpdate
        if container.contains(.js) { js = try container.gsonString(forKey: .js) }
        if container.contains(.showRule) { showRule = try container.gsonString(forKey: .showRule) }
        if container.contains(.sourceUrl) { sourceUrl = try container.gsonString(forKey: .sourceUrl) }
    }
}

public typealias RuleSubRepository = Repository<RuleSub>
