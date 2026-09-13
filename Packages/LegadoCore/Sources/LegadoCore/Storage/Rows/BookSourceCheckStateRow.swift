import Foundation
import GRDB

public struct BookSourceCheckStateRow: StorageRow {
    public static let databaseTableName = "book_source_check_states"
    public var bookSourceUrl = ""
    public var revision = UUID().uuidString
    public var sourceRevision = UUID().uuidString
    public var status = "NEEDS_CHECK"
    public var checkedAt: Int64 = 0
    public var detail = ""

    public init() {}
}

public typealias BookSourceCheckStateRepository = Repository<BookSourceCheckStateRow>
