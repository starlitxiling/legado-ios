import Foundation
import GRDB

public typealias BookSourceRepository = Repository<BookSourceRow>

public struct BookSourceSummary: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let group: String
    public let enabled: Bool
    public let order: Int
    public var groups: [String] {
        group.components(separatedBy: CharacterSet(charactersIn: ",;，；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

extension Repository where Record == BookSourceRow {
    public func summaries() async throws -> [BookSourceSummary] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT bookSourceUrl, bookSourceName, bookSourceGroup, enabled, customOrder FROM book_sources ORDER BY customOrder, bookSourceUrl").map {
                BookSourceSummary(id: $0["bookSourceUrl"], name: $0["bookSourceName"], group: $0["bookSourceGroup"] ?? "",
                    enabled: $0["enabled"], order: $0["customOrder"])
            }
        }
    }

    public func enabledURLs() async throws -> [String] {
        try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT bookSourceUrl FROM book_sources WHERE enabled = 1 ORDER BY customOrder, bookSourceUrl")
        }
    }

    public func get(bookSourceUrl: String) async throws -> BookSourceRow? {
        try await database.writer.read { db in try BookSourceRow.fetchOne(db, key: bookSourceUrl) }
    }

    public func list(enabled: Bool? = nil) async throws -> [BookSourceRow] {
        try await database.writer.read { db in
            if let enabled {
                return try BookSourceRow.fetchAll(db, sql: "SELECT * FROM book_sources WHERE enabled = ? ORDER BY customOrder, bookSourceUrl", arguments: [enabled])
            }
            return try BookSourceRow.fetchAll(db, sql: "SELECT * FROM book_sources ORDER BY customOrder, bookSourceUrl")
        }
    }
}
