import Foundation
import GRDB

public extension Repository where Record == BookSourceRow {
    func sourceForBookURL(_ bookURL: String) async throws -> BookSourceRow? {
        let parsed = UrlOptions.parse(bookURL)
        guard let url = URL(string: parsed.url), let scheme = url.scheme, let host = url.host else { return nil }
        let baseURL = scheme + "://" + host + (url.port.map { ":" + String($0) } ?? "")
        @Sendable func matches(_ pattern: String?) -> Bool {
            guard let pattern, !pattern.isEmpty, pattern != "NONE",
                  let regex = try? NSRegularExpression(pattern: "\\A(?:" + pattern + ")\\z") else { return false }
            return regex.firstMatch(in: bookURL, range: NSRange(bookURL.startIndex..., in: bookURL)) != nil
        }
        return try await database.writer.read { db in
            if let origin = parsed.options.origin,
               let specified = try BookSourceRow.fetchOne(db, key: origin), matches(specified.bookUrlPattern) { return specified }
            if let sameOrigin = try BookSourceRow.fetchOne(db,
                sql: "SELECT * FROM book_sources WHERE enabled = 1 AND bookSourceUrl = ?", arguments: [baseURL]) { return sameOrigin }
            let patterns = try Row.fetchAll(db, sql: "SELECT bookSourceUrl, bookUrlPattern FROM book_sources WHERE enabled = 1 AND trim(bookUrlPattern) <> '' AND trim(bookUrlPattern) <> 'NONE' ORDER BY customOrder, bookSourceUrl")
            for pattern in patterns where matches(pattern["bookUrlPattern"]) {
                return try BookSourceRow.fetchOne(db, key: pattern["bookSourceUrl"] as String)
            }
            return nil
        }
    }
}

public extension Repository where Record == Server {
    func get(id: Int64) async throws -> Server? {
        try await database.writer.read { db in try Server.fetchOne(db, key: id) }
    }
}
