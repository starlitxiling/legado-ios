import Foundation
import Observation
import LegadoCore

struct BookshelfBookListEntry: Hashable, Sendable {
    let name: String
    let author: String
}

enum BookshelfBookList {
    static let maximumBytes = 10 * 1024 * 1024

    static func decode(_ data: Data) throws -> [BookshelfBookListEntry] {
        guard data.count <= maximumBytes,
              let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw Failure.invalidFormat }
        var seen = Set<BookshelfBookListEntry>()
        return try objects.compactMap { object in
            guard let name = object["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  object["author"] == nil || object["author"] is NSNull || object["author"] is String else { throw Failure.invalidFormat }
            let entry = BookshelfBookListEntry(name: name, author: object["author"] as? String ?? "")
            return seen.insert(entry).inserted ? entry : nil
        }
    }

    static func encode(_ books: [BookRow]) throws -> Data {
        let objects = books.map { book -> [String: String] in
            var item = ["name": book.name, "author": book.author]
            item["intro"] = book.customIntro?.isEmpty == false ? book.customIntro : book.intro
            return item
        }
        return try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    enum Failure: LocalizedError {
        case invalidFormat, noMatch(String)
        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "书单须为 JSON 数组，每项包含非空 name 和可选 author，大小不能超过 10 MB。"
            case .noMatch(let name): return "没有搜索到：" + name
            }
        }
    }
}

@Observable
@MainActor
final class BookshelfBookListModel {
    var input = ""
    private(set) var isImporting = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var failures: [String] = []
    private let database: AppDatabase
    private let client: any HttpClient
    private let concurrency: Int

    init(database: AppDatabase, client: any HttpClient, concurrency: Int = 8) {
        self.database = database; self.client = client; self.concurrency = min(128, max(1, concurrency))
    }

    func importBooks(groupID: Int64) async {
        guard !isImporting else { return }
        isImporting = true; completed = 0; total = 0; failures = []
        defer {
            isImporting = false
            AppLogStore.shared.append("Book list import: \(completed)/\(total), failures: \(failures.count), cancelled: \(Task.isCancelled)")
        }
        do {
            let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let data: Data
            if let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                let response: HttpResponse
                if let limited = client as? any ResponseLimitedHttpClient {
                    response = try await limited.send(HttpRequest(url: url), maximumResponseBytes: BookshelfBookList.maximumBytes)
                } else { response = try await client.send(HttpRequest(url: url)) }
                guard (200..<300).contains(response.status) else { throw WebDavError.httpStatus(response.status) }
                data = response.body
            } else { data = Data(text.utf8) }
            let entries = try BookshelfBookList.decode(data)
            total = entries.count
            let existing = Set(try await BookshelfRepository(database: database).all().map {
                BookshelfBookListEntry(name: $0.name, author: $0.author)
            })
            let urls = try await BookSourceRepository(database: database).enabledURLs()
            let database = database, client = client
            var errors: [Int: String] = [:]
            try await withThrowingTaskGroup(of: (Int, String?).self) { tasks in
                defer { tasks.cancelAll() }
                var next = 0
                func enqueue() {
                    let index = next, entry = entries[next]
                    next += 1
                    tasks.addTask {
                        do {
                            try Task.checkCancellation()
                            if !existing.contains(entry) {
                                try await Self.importBook(entry, sourceURLs: urls, groupID: groupID, database: database, client: client)
                            }
                            return (index, nil)
                        } catch {
                            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                            return (index, error.presentation(operation: "导入书单书籍", subject: entry.name + " · " + entry.author)?.displayText)
                        }
                    }
                }
                for _ in 0..<min(concurrency, entries.count) { enqueue() }
                for try await (index, error) in tasks {
                    try Task.checkCancellation()
                    completed += 1
                    errors[index] = error
                    failures = errors.sorted { $0.key < $1.key }.map(\.value)
                    if next < entries.count { enqueue() }
                }
            }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                failures = error.presentation(operation: "导入书单") .map { [$0.displayText] } ?? []
            }
        }
    }

    private nonisolated static func importBook(_ entry: BookshelfBookListEntry, sourceURLs: [String], groupID: Int64,
                                               database: AppDatabase, client: any HttpClient) async throws {
        let sources = BookSourceRepository(database: database)
        for url in sourceURLs {
            try Task.checkCancellation()
            let book: Book
            do {
                guard let row = try await sources.get(bookSourceUrl: url), row.enabled else { continue }
                book = try await WebBook(source: DiscoveryStorage.source(row), client: client)
                    .preciseSearch(name: entry.name, author: entry.author)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                continue
            }
            var incoming = try DiscoveryStorage.row(book, defaults: BookRow())
            if groupID > 0 { incoming.group = groupID }
            let saved = incoming
            try Task.checkCancellation()
            try await database.write { db in
                guard try BookRow.matching(bookUrl: saved.bookUrl, name: saved.name, author: saved.author, in: db) == nil else { return }
                try saved.save(in: db)
            }
            return
        }
        throw BookshelfBookList.Failure.noMatch(entry.name + " " + entry.author)
    }
}
