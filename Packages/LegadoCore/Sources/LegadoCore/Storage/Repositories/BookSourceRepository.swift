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
        try await database.writer.read { db in
            if let exact = try BookSourceRow.fetchOne(db, key: bookSourceUrl) { return exact }
            let urls = try String.fetchAll(db, sql: "SELECT bookSourceUrl FROM book_sources")
            guard let match = BookSourceURL.match(bookSourceUrl, candidates: urls) else { return nil }
            return try BookSourceRow.fetchOne(db, key: match)
        }
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

public struct SourceManagementMetadata: Sendable {
    public let usageCount: Int
    public let check: BookSourceCheckState?
}

extension Repository where Record == BookSourceRow {
    public func managementMetadata() async throws -> [String: SourceManagementMetadata] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.bookSourceUrl, (SELECT COUNT(*) FROM books b WHERE b.origin = s.bookSourceUrl AND (b.type & 1024) = 0) AS usageCount,
                       state.value AS checkState
                FROM book_sources s LEFT JOIN source_state state ON state.source = s.bookSourceUrl AND state.key = 'checkState'
                """)
            return try Dictionary(uniqueKeysWithValues: rows.map { row in
                let state: String? = row["checkState"]
                let check = try state.map { try JSONDecoder().decode(BookSourceCheckState.self, from: Data($0.utf8)) }
                return (row["bookSourceUrl"] as String, SourceManagementMetadata(usageCount: row["usageCount"], check: check))
            })
        }
    }
}

public enum BookSourceURL {
    public static func normalized(_ value: String) -> String {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        value = String(value.prefix { $0 != "#" })
        while value.hasSuffix("/") { value.removeLast() }
        guard var components = URLComponents(string: value) else { return value }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        return components.string ?? value
    }

    public static func match(_ origin: String, candidates: [String]) -> String? {
        if candidates.contains(origin) { return origin }
        let target = normalized(origin)
        guard !target.isEmpty else { return nil }
        let matches = candidates.filter { normalized($0) == target }
        return matches.count == 1 ? matches[0] : nil
    }
}
