import GRDB

public typealias BookGroupRepository = Repository<BookGroupRow>

extension Repository where Record == BookGroupRow {
    public func get(groupID: Int64) async throws -> BookGroupRow? {
        try await database.writer.read { db in try BookGroupRow.fetchOne(db, key: groupID) }
    }

    public func list() async throws -> [BookGroupRow] {
        try await database.writer.read { db in
            try BookGroupRow.fetchAll(db, sql: "SELECT * FROM book_groups ORDER BY \"order\", groupId")
        }
    }
}
