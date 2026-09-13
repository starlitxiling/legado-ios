import Foundation
import GRDB

public struct RssRepository: Sendable {
    private let database: AppDatabase
    public init(database: AppDatabase) { self.database = database }
    public func service(client: any HttpClient) -> RssService { RssService(client: client, database: database) }
    public func sources() async throws -> [RssSource] {
        try await database.writer.read { try RssSource.fetchAll($0, sql: "SELECT * FROM rssSources ORDER BY customOrder, sourceName") }
    }
    public func saveSources(_ values: [RssSource]) async throws {
        try await database.write { db in for value in values { try value.save(db) } }
    }
    public func renameSource(_ value: RssSource, replacing oldURL: String) async throws {
        try await database.write { db in
            try value.save(db)
            if value.sourceUrl != oldURL {
                for table in ["rssArticles", "rssStars", "rssReadRecords"] {
                    try db.execute(sql: "UPDATE \(table) SET origin = ? WHERE origin = ?", arguments: [value.sourceUrl, oldURL])
                }
                try db.execute(sql: "DELETE FROM rssSources WHERE sourceUrl = ?", arguments: [oldURL])
            }
        }
    }
    public func deleteSource(_ url: String) async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM rssArticles WHERE origin = ?", arguments: [url])
            try db.execute(sql: "DELETE FROM rssSources WHERE sourceUrl = ?", arguments: [url])
        }
    }
    public func saveArticles(_ values: [RssArticle], replacingColumn: RssColumn? = nil, origin: String? = nil) async throws {
        try await database.write { db in
            if let column = replacingColumn, let origin {
                try db.execute(sql: "DELETE FROM rssArticles WHERE origin = ? AND sort = ?", arguments: [origin, column.name])
            }
            for var value in values {
                if let record = try RssReadRecord.fetchOne(db, key: value.link) { value.read = record.read }
                try value.save(db)
            }
        }
    }
    public func articles(origin: String, sort: String) async throws -> [RssArticle] {
        try await database.writer.read { db in
            try RssArticle.fetchAll(db, sql: "SELECT * FROM rssArticles WHERE origin = ? AND sort = ? ORDER BY \"order\"", arguments: [origin, sort])
        }
    }
    public func stars() async throws -> [RssStar] {
        try await database.writer.read { try RssStar.fetchAll($0, sql: "SELECT * FROM rssStars ORDER BY starTime DESC") }
    }
    public func saveStars(_ values: [RssStar]) async throws {
        try await database.write { db in for value in values { try value.save(db) } }
    }
    public func setStar(_ article: RssArticle, starred: Bool, time: Int64) async throws {
        let star = try article.star(time: time)
        try await database.write { db in
            if starred { try star.save(db) }
            else { try db.execute(sql: "DELETE FROM rssStars WHERE origin = ? AND link = ?", arguments: [article.origin, article.link]) }
        }
    }
    public func markRead(_ article: RssArticle, time: Int64) async throws {
        var record = RssReadRecord()
        record.record = article.link; record.origin = article.origin; record.sort = article.sort
        record.title = article.title; record.readTime = time; record.image = article.image
        record.type = article.type; record.durPos = article.durPos; record.pubDate = article.pubDate
        let value = record
        try await database.write { db in
            try value.save(db)
            try db.execute(sql: "UPDATE rssArticles SET read = 1 WHERE link = ?", arguments: [article.link])
        }
    }
}
