import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class AddBookURLModel {
    var input = ""
    private(set) var isAdding = false
    private(set) var completed = 0
    private(set) var failures: [String] = []
    private let database: AppDatabase
    private let client: any HttpClient

    init(database: AppDatabase, client: any HttpClient) {
        self.database = database
        self.client = client
    }

    func add(groupID: Int64) async {
        guard !isAdding else { return }
        let lines = input.components(separatedBy: .newlines)
        isAdding = true; completed = 0; failures = []
        defer { isAdding = false }
        for (index, line) in lines.enumerated() {
            let url = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { continue }
            do {
                try Task.checkCancellation()
                try await add(url, groupID: groupID)
                completed += 1
            } catch is CancellationError { return }
            catch let error as URLError where error.code == .cancelled { return }
            catch { if let failure = error.presentation(operation: "添加书籍网址", subject: "第 \(index + 1) 行 · \(url)") { failures.append(failure.displayText) } }
        }
    }

    private func add(_ url: String, groupID: Int64) async throws {
        let shelf = BookshelfRepository(database: database)
        if try await shelf.get(bookUrl: url) != nil {
            try await database.write { db in
                guard var row = try BookRow.matching(bookUrl: url, name: "", author: "", in: db), row.bookUrl == url else { return }
                if groupID > 0 { row.group |= groupID }
                row.type &= ~DiscoveryStorage.hiddenBook
                try row.save(in: db)
            }
            return
        }
        guard let row = try await BookSourceRepository(database: database).sourceForBookURL(url) else {
            throw AddError.sourceNotFound
        }
        let source = try DiscoveryStorage.source(row)
        var book = Book(); book.bookUrl = url; book.origin = source.bookSourceUrl; book.originName = source.bookSourceName
        let web = WebBook(source: source, client: client)
        book = try await web.bookInfo(book)
        let previous = try await DiscoveryStorage.matchingBook(book, in: shelf)
        let chapters: [BookChapterRow]?
        if previous != nil {
            chapters = try await web.chapterList(book: &book).map { try DiscoveryStorage.row($0, defaults: BookChapterRow()) }
        } else { chapters = nil }
        let incoming = try DiscoveryStorage.row(book, defaults: BookRow())
        let minimumOrder = try await shelf.all().map(\.order).min() ?? 0
        try Task.checkCancellation()
        try await database.write { db in
            var saved = incoming
            if let previous = try BookRow.matching(bookUrl: incoming.bookUrl, name: incoming.name, author: incoming.author, in: db) {
                saved = DiscoveryStorage.preservingReading(previous, in: saved)
                if let chapters {
                    saved.durChapterIndex = ChapterLocator.locate(oldIndex: previous.durChapterIndex,
                        oldTitle: previous.durChapterTitle, oldCount: previous.totalChapterNum, titles: chapters.map(\.title))
                    if chapters.indices.contains(saved.durChapterIndex) { saved.durChapterTitle = chapters[saved.durChapterIndex].title }
                }
            } else { saved.order = minimumOrder == Int.min ? Int.min : minimumOrder - 1 }
            if groupID > 0 { saved.group |= groupID }
            saved.type &= ~DiscoveryStorage.hiddenBook
            try saved.replaceByIdentity(in: db)
            if let chapters { try BookChapterRow.replaceAll(bookUrl: saved.bookUrl, chapters: chapters, in: db) }
        }
    }

    private enum AddError: LocalizedError {
        case sourceNotFound
        var errorDescription: String? { "未找到匹配的书源" }
    }
}
