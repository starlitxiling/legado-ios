import Foundation
import LegadoCore

enum DiscoveryStorage {
    static let hiddenBook = 1024

    static func row<Value: Encodable, Row: StorageRow>(_ value: Value, defaults: Row) throws -> Row {
        let encoder = JSONEncoder()
        var fields = try JSONSerialization.jsonObject(with: encoder.encode(defaults)) as! [String: Any]
        let incoming = try JSONSerialization.jsonObject(with: encoder.encode(value)) as! [String: Any]
        for (key, value) in incoming {
            if value is NSNull, fields[key] != nil { continue }
            if value is [String: Any] || value is [Any] {
                fields[key] = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
            } else {
                fields[key] = value
            }
        }
        return try JSONDecoder().decode(Row.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    static func source(_ row: BookSourceRow) throws -> BookSource {
        try JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode(row))
    }

    static func book(_ row: BookRow) throws -> Book {
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as! [String: Any]
        if let config = row.readConfig {
            fields["readConfig"] = try JSONSerialization.jsonObject(with: Data(config.utf8))
        }
        return try JSONDecoder().decode(Book.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    static func matchingBook(_ book: Book, in repository: BookshelfRepository) async throws -> BookRow? {
        if let row = try await repository.get(bookUrl: book.bookUrl ?? "") { return row }
        return try await repository.all().first { $0.name == book.name && $0.author == book.author }
    }

    static func preservingReading(_ saved: BookRow, in incoming: BookRow) -> BookRow {
        var row = incoming
        row.type = (incoming.type & ~hiddenBook) | (saved.type & hiddenBook)
        row.group = saved.group
        row.order = saved.order
        row.durChapterIndex = saved.durChapterIndex
        row.durChapterPos = saved.durChapterPos
        row.durChapterTitle = saved.durChapterTitle
        row.durChapterTime = saved.durChapterTime
        row.readConfig = saved.readConfig
        row.customCoverUrl = saved.customCoverUrl
        row.persistedCoverUrl = saved.persistedCoverUrl
        row.customIntro = saved.customIntro
        row.customTag = saved.customTag
        row.canUpdate = saved.canUpdate
        return row
    }
}
