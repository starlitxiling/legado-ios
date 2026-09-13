import Foundation
import GRDB

public struct BookProgress: Codable, Equatable, Sendable {
    public var name: String
    public var author: String
    public var durChapterIndex: Int
    public var durChapterPos: Int
    public var durChapterTime: Int64
    public var durChapterTitle: String?

    public init(book: BookRow) {
        name = book.name; author = book.author; durChapterIndex = book.durChapterIndex
        durChapterPos = book.durChapterPos; durChapterTime = book.durChapterTime; durChapterTitle = book.durChapterTitle
    }
}

public struct BookProgressSync: Sendable {
    public enum ReadingAction: Equatable, Sendable { case none, synchronize, upload }

    public static func readingAction(syncEnabled: Bool, plusEnabled: Bool, exiting: Bool) -> ReadingAction {
        guard syncEnabled else { return .none }
        if plusEnabled { return .synchronize }
        return exiting ? .upload : .none
    }
    private let client: WebDavClient
    private let directory: String
    public init(client: WebDavClient, directory: String = "legado") {
        self.client = client; self.directory = directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public static func fileName(name: String, author: String) -> String {
        BackupExporter.normalizeFileName(name + "_" + author) + ".json"
    }

    private func progressURL(_ book: BookRow) throws -> URL {
        let parent = try client.url(path: directory + "/bookProgress/")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let name = Self.fileName(name: book.name, author: book.author).addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: parent.absoluteString + name) else { throw WebDavError.invalidURL }
        return url
    }

    public func upload(_ book: BookRow, now: Int64) async throws -> BookRow {
        try await client.ensureCollection(client.url(path: directory + "/"))
        try await client.ensureCollection(client.url(path: directory + "/bookProgress/"))
        try await client.put(JSONEncoder().encode(BookProgress(book: book)), to: progressURL(book), contentType: "application/json")
        var updated = book; updated.syncTime = now
        return updated
    }

    public func download(_ book: BookRow, now: Int64) async throws -> BookRow {
        let url = try progressURL(book)
        let files: [WebDavFile]
        do { files = try await client.propfind(url, depth: 0) }
        catch WebDavError.httpStatus(404) { return book }
        guard let file = files.first(where: { $0.url == url }), let modified = file.lastModified,
              modified.timeIntervalSince1970 * 1000 > Double(book.syncTime) else { return book }
        let remote = try JSONDecoder().decode(BookProgress.self, from: await client.get(url, maximumResponseBytes: 1024 * 1024))
        return Self.merge(book: book, remote: remote, remoteModified: Int64(modified.timeIntervalSince1970 * 1000), now: now)
    }

    public func downloadAll(_ books: [BookRow], now: Int64) async throws -> [BookRow] {
        let files = try await client.propfind(client.url(path: directory + "/bookProgress/"))
        var result: [BookRow] = []
        for book in books {
            try Task.checkCancellation()
            guard let file = files.first(where: { !$0.isDirectory && $0.displayName == Self.fileName(name: book.name, author: book.author) }),
                  let modified = file.lastModified,
                  modified.timeIntervalSince1970 * 1000 > Double(book.syncTime) else { result.append(book); continue }
            let remote = try JSONDecoder().decode(BookProgress.self, from: await client.get(progressURL(book), maximumResponseBytes: 1024 * 1024))
            result.append(Self.merge(book: book, remote: remote, remoteModified: Int64(modified.timeIntervalSince1970 * 1000), now: now))
        }
        return result
    }

    public struct ReadingResult: Sendable {
        public let book: BookRow
        public let remoteProgress: BookProgress?
    }

    public func synchronizeReading(_ book: BookRow, now: Int64) async throws -> ReadingResult {
        let remote: BookProgress?
        do {
            remote = try JSONDecoder().decode(BookProgress.self, from: await client.get(progressURL(book), maximumResponseBytes: 1024 * 1024))
        } catch WebDavError.httpStatus(404) { remote = nil }
        guard let remote else { return ReadingResult(book: try await upload(book, now: now), remoteProgress: nil) }
        guard remote.name == book.name, remote.author == book.author else { return ReadingResult(book: book, remoteProgress: nil) }
        if remote.durChapterIndex < book.durChapterIndex ||
            (remote.durChapterIndex == book.durChapterIndex && remote.durChapterPos < book.durChapterPos) {
            return ReadingResult(book: try await upload(book, now: now), remoteProgress: nil)
        }
        let ahead = remote.durChapterIndex > book.durChapterIndex || remote.durChapterPos > book.durChapterPos
        return ReadingResult(book: book, remoteProgress: ahead ? remote : nil)
    }

    public static func merge(book: BookRow, remote: BookProgress, remoteModified: Int64, now: Int64) -> BookRow {
        guard remoteModified > book.syncTime,
              remote.name == book.name, remote.author == book.author,
              remote.durChapterIndex > book.durChapterIndex ||
                (remote.durChapterIndex == book.durChapterIndex && remote.durChapterPos > book.durChapterPos) else { return book }
        var updated = book
        updated.durChapterIndex = remote.durChapterIndex; updated.durChapterPos = remote.durChapterPos
        updated.durChapterTime = remote.durChapterTime; updated.durChapterTitle = remote.durChapterTitle
        updated.syncTime = now
        return updated
    }

    public static func save(_ updated: BookRow, replacing original: BookRow, database: AppDatabase) async throws {
        try await database.write { db in
            // 网络请求期间的阅读或书籍编辑必须保留，只在原进度仍有效时写入进度列。
            try db.execute(sql: """
                UPDATE books SET durChapterIndex = ?, durChapterPos = ?, durChapterTime = ?, durChapterTitle = ?, syncTime = ?
                WHERE bookUrl = ? AND syncTime = ? AND durChapterTime = ? AND durChapterIndex = ? AND durChapterPos = ?
                """, arguments: [updated.durChapterIndex, updated.durChapterPos, updated.durChapterTime, updated.durChapterTitle, updated.syncTime,
                                   original.bookUrl, original.syncTime, original.durChapterTime, original.durChapterIndex, original.durChapterPos])
        }
    }
}
