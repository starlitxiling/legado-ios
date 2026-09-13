import GRDB

public typealias ReadProgressRepository = Repository<ReadRecordRow>

extension Repository where Record == ReadRecordRow {
    public func get(deviceID: String, bookName: String, author: String) async throws -> ReadRecordRow? {
        try await database.writer.read { db in
            try ReadRecordRow.fetchOne(db, key: ["deviceId": deviceID, "bookName": bookName, "author": author])
        }
    }

    public func list(bookName: String, author: String) async throws -> [ReadRecordRow] {
        try await database.writer.read { db in
            try ReadRecordRow.fetchAll(db, sql: "SELECT * FROM readRecord WHERE bookName = ? AND author = ? ORDER BY lastRead DESC, deviceId", arguments: [bookName, author])
        }
    }

    /// 事务中累加时长，迟到的阅读区间不覆盖较新的快照。
    public func record(_ snapshot: ReadRecordRow, elapsed: Int64) async throws {
        try await database.writer.write { db in
            let current = try ReadRecordRow.fetchOne(db, key: ["deviceId": snapshot.deviceId, "bookName": snapshot.bookName, "author": snapshot.author])
            var saved = current.map { $0.lastRead > snapshot.lastRead ? $0 : snapshot } ?? snapshot
            let (total, overflow) = (current?.readTime ?? 0).addingReportingOverflow(max(0, elapsed))
            guard !overflow else { throw ReadDurationError.overflow }
            saved.readTime = total
            saved.resolvedAuthor = current?.resolvedAuthor ?? snapshot.resolvedAuthor
            try saved.save(db)
        }
    }
}

public enum ReadDurationError: Error {
    case overflow
}
