import GRDB

public struct Repository<Record: StorageRow>: Sendable {
    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    @discardableResult
    public func insert(_ record: Record) async throws -> Record {
        try await database.writer.write { db in
            var saved = record
            try saved.insert(db)
            return saved
        }
    }

    /// 按主键更新；不存在时使用 Row 定义的插入冲突策略。
    @discardableResult
    public func upsert(_ record: Record) async throws -> Record {
        try await database.writer.write { db in
            var saved = record
            try saved.save(db)
            return saved
        }
    }

    public func upsert(_ records: [Record]) async throws {
        try await database.writer.write { db in
            for var record in records {
                try record.save(db)
            }
        }
    }

    public func update(_ record: Record) async throws {
        try await database.writer.write { db in try record.update(db) }
    }

    @discardableResult
    public func delete(_ record: Record) async throws -> Bool {
        try await database.writer.write { db in try record.delete(db) }
    }

    public func all() async throws -> [Record] {
        try await database.writer.read { db in try Record.fetchAll(db) }
    }
}
