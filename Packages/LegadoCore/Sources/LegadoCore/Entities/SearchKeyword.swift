import Foundation
import GRDB

public struct SearchKeyword: StorageRow {
    public static let databaseTableName = "search_keywords"
    public var word: String = ""
    public var usage: Int = 1
    public var lastUseTime: Int64 = 0

    public init() {}

    public init(row: Row) {
        word = row["word"]
        usage = row["usage"]
        lastUseTime = row["lastUseTime"]
    }

    private enum CodingKeys: String, CodingKey {
        case word, usage, lastUseTime
    }

    public init(from decoder: Decoder) throws {
        self.init()
        lastUseTime = GsonDecoding.time(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        word = try container.gsonString(forKey: .word) ?? word
        usage = try container.gsonInt(forKey: .usage) ?? usage
        lastUseTime = try container.gsonLong(forKey: .lastUseTime) ?? lastUseTime
    }
}

public typealias SearchKeywordRepository = Repository<SearchKeyword>
