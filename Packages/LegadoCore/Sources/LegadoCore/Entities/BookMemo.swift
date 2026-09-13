import Foundation
import GRDB

public struct BookMemo: StorageRow {
    public static let databaseTableName = "book_memos"
    public var bookUrl: String = ""
    public var content: String = ""
    public var updatedAt: Int64 = 0

    public init() {}

    public init(row: Row) {
        bookUrl = row["bookUrl"]
        content = row["content"]
        updatedAt = row["updatedAt"]
    }

    private enum CodingKeys: String, CodingKey {
        case bookUrl, content, updatedAt
    }

    public init(from decoder: Decoder) throws {
        self.init()
        updatedAt = GsonDecoding.time(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookUrl = try container.gsonString(forKey: .bookUrl) ?? bookUrl
        content = try container.gsonString(forKey: .content) ?? content
        updatedAt = try container.gsonLong(forKey: .updatedAt) ?? updatedAt
    }
}

public typealias BookMemoRepository = Repository<BookMemo>
