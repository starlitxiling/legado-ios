import Foundation
import GRDB

public struct Cache: StorageRow {
    public static let databaseTableName = "caches"
    public var key: String = ""
    public var value: String? = nil
    public var deadline: Int64 = 0

    public init() {}

    public init(row: Row) {
        key = row["key"]
        value = row["value"]
        deadline = row["deadline"]
    }

    private enum CodingKeys: String, CodingKey {
        case key, value, deadline
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.gsonString(forKey: .key) ?? key
        if container.contains(.value) { value = try container.gsonString(forKey: .value) }
        deadline = try container.gsonLong(forKey: .deadline) ?? deadline
    }
}

public typealias CacheRepository = Repository<Cache>
