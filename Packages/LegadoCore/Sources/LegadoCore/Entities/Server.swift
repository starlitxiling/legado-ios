import Foundation
import GRDB

public struct Server: StorageRow {
    public static let databaseTableName = "servers"
    public var id: Int64 = 0
    public var name: String = ""
    public var type: String = "WEBDAV"
    public var config: String? = nil
    public var sortNumber: Int = 0

    public init() {}

    public init(row: Row) {
        id = row["id"]
        name = row["name"]
        type = row["type"]
        config = row["config"]
        sortNumber = row["sortNumber"]
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, type, config, sortNumber
    }

    public init(from decoder: Decoder) throws {
        self.init()
        id = GsonDecoding.time(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.gsonLong(forKey: .id) ?? id
        name = try container.gsonString(forKey: .name) ?? name
        type = try container.gsonString(forKey: .type) ?? type
        if container.contains(.config) { config = try container.gsonString(forKey: .config) }
        sortNumber = try container.gsonInt(forKey: .sortNumber) ?? sortNumber
    }
}

public typealias ServerRepository = Repository<Server>
