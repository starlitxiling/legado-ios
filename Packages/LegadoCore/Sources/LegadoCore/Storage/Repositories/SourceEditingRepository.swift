import Foundation
import GRDB

extension Repository where Record == BookSourceRow {
    public func editSources(_ transform: @escaping @Sendable ([BookSourceRow]) throws -> [BookSourceRow]) async throws {
        try await database.writer.write { db in
            let current = try BookSourceRow.fetchAll(db, sql: "SELECT * FROM book_sources ORDER BY customOrder, bookSourceUrl")
            for var row in try transform(current) { try row.save(db) }
        }
    }

    public func saveEdited(_ source: BookSourceRow, replacing oldURL: String?) async throws {
        try await database.writer.write { db in
            if oldURL != source.bookSourceUrl,
               try BookSourceRow.fetchOne(db, key: source.bookSourceUrl) != nil {
                throw NSError(domain: "SourceEditing", code: 1, userInfo: [NSLocalizedDescriptionKey: "已存在相同地址的书源"])
            }
            var saved = source
            try saved.save(db)
            if let oldURL, oldURL != source.bookSourceUrl { _ = try BookSourceRow.deleteOne(db, key: oldURL) }
        }
    }
}
