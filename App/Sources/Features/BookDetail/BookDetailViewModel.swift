import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class BookDetailViewModel {
    private(set) var results: [SearchBook]
    private(set) var selectedSourceIndex = 0
    private(set) var book: Book?
    private(set) var source: BookSource?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isOnBookshelf = false
    var userError: UserFacingError?
    var errorMessage: String? { userError?.displayText }

    private let sources: BookSourceRepository
    private let bookshelf: BookshelfRepository
    private let client: any HttpClient
    private var generation = 0

    init(results: [SearchBook], sources: BookSourceRepository,
         bookshelf: BookshelfRepository, client: any HttpClient, initialBook: Book? = nil) {
        self.results = results
        self.book = initialBook
        self.isOnBookshelf = initialBook != nil
        self.sources = sources
        self.bookshelf = bookshelf
        self.client = client
    }

    func selectSource(_ index: Int) async {
        guard results.indices.contains(index), !isSaving else { return }
        selectedSourceIndex = index
        await load()
    }

    func load() async {
        guard results.indices.contains(selectedSourceIndex), !isSaving else { return }
        generation += 1
        let request = generation
        let result = results[selectedSourceIndex]
        let previous = book
        isLoading = true
        book = nil
        source = nil
        isOnBookshelf = false
        userError = nil
        defer { if request == generation { isLoading = false } }
        do {
            guard let row = try await sources.resolveForBookOrigin(result.origin ?? "") else {
                throw WebBookError.missingRule("书源不存在")
            }
            let selected = try DiscoveryStorage.source(row)
            let saved = try await bookshelf.get(bookUrl: result.bookUrl ?? "")
            let web = WebBook(source: selected, client: client)
            var loaded: Book
            if let saved {
                loaded = try await web.bookInfo(DiscoveryStorage.book(saved))
            } else {
                loaded = try await web.bookInfo(result)
            }
            let matching = try await DiscoveryStorage.matchingBook(loaded, in: bookshelf)
            let old = try previous.map { try DiscoveryStorage.row($0, defaults: BookRow()) } ?? matching
            if let old, old.name == loaded.name, old.author == loaded.author {
                loaded = try DiscoveryStorage.book(DiscoveryStorage.preservingReading(old,
                    in: DiscoveryStorage.row(loaded, defaults: BookRow())))
                loaded.totalChapterNum = old.totalChapterNum
            }
            guard request == generation, !Task.isCancelled else { return }
            if saved != nil, let current = try await bookshelf.get(bookUrl: loaded.bookUrl ?? "") {
                var updated = try DiscoveryStorage.preservingReading(current, in: DiscoveryStorage.row(loaded, defaults: current))
                updated.totalChapterNum = current.totalChapterNum
                guard request == generation, !Task.isCancelled else { return }
                try await bookshelf.upsert(updated)
                loaded = try DiscoveryStorage.book(updated)
            }
            guard request == generation, !Task.isCancelled else { return }
            book = loaded
            source = selected
            isOnBookshelf = saved.map { $0.type & DiscoveryStorage.hiddenBook == 0 } ?? false
        } catch {
            if request == generation, !Task.isCancelled { userError = error.presentation(operation: "加载书籍详情", subject: result.name) }
        }
    }

    func refreshShelfState() async {
        guard let url = book?.bookUrl else { return }
        do {
            let saved = try await bookshelf.get(bookUrl: url)
            let sourceRow = try await sources.resolveForBookOrigin(book?.origin ?? "")
            guard book?.bookUrl == url else { return }
            if let saved { book = try DiscoveryStorage.book(saved) }
            source = try sourceRow.map(DiscoveryStorage.source)
            isOnBookshelf = saved.map { $0.type & DiscoveryStorage.hiddenBook == 0 } ?? false
        } catch { userError = error.presentation(operation: "刷新书架状态", subject: book?.name) }
    }

    func selectResult(_ result: SearchBook) async {
        if let index = results.firstIndex(where: { $0.bookUrl == result.bookUrl }) {
            await selectSource(index)
        } else {
            results.append(result)
            await selectSource(results.count - 1)
        }
    }

    func prepareForReading(database: AppDatabase) async -> Book? {
        guard let book, !isLoading, !isSaving else { return nil }
        isSaving = true; userError = nil
        defer { isSaving = false }
        do {
            if let matching = try await DiscoveryStorage.matchingBook(book, in: bookshelf),
               matching.bookUrl != book.bookUrl, let source {
                var updated = book
                let chapters = try await WebBook(source: source, client: client).chapterList(book: &updated)
                let rows = try chapters.map { try DiscoveryStorage.row($0, defaults: BookChapterRow()) }
                self.book = try await SourceChangeTransaction.save(book: updated, previous: book, chapters: rows, database: database)
            } else {
                self.book = try DiscoveryStorage.book(try await storedBook())
            }
            await refreshShelfState()
            return self.book
        } catch { userError = error.presentation(operation: "准备阅读", subject: book.name); return nil }
    }

    func setCanUpdate(_ enabled: Bool) async {
        await edit { book in
            book.canUpdate = enabled
            if !enabled { book.type &= ~16 }
        }
    }

    func setSplitLongChapter(_ enabled: Bool) async {
        await edit { book in
            var config = book.readConfig ?? ReadConfig()
            config.splitLongChapter = enabled; book.readConfig = config
        }
    }

    func setVariable(_ value: String) async {
        do {
            if !value.isEmpty {
                guard try JSONSerialization.jsonObject(with: Data(value.utf8)) is [String: String] else {
                    throw BookDetailActionError.invalidVariable
                }
            }
            await edit { $0.variable = value.isEmpty ? nil : value }
        } catch { userError = error.presentation(operation: "保存书籍变量", subject: book?.name) }
    }

    func setGroups(_ mask: Int64) async { await edit { $0.group = mask } }

    func moveToTop() async {
        guard isOnBookshelf, !isSaving else { return }
        isSaving = true; userError = nil
        defer { isSaving = false }
        do { book = try DiscoveryStorage.book(try await bookshelf.saveAtTop(try await storedBook())) }
        catch { userError = error.presentation(operation: "置顶书籍", subject: book?.name) }
    }

    func storedBook() async throws -> BookRow {
        guard let book, let url = book.bookUrl, !url.isEmpty else { throw BookshelfEditError.missingBook }
        if let saved = try await bookshelf.get(bookUrl: url) { return saved }
        var row = try DiscoveryStorage.row(book, defaults: BookRow())
        row.type |= DiscoveryStorage.hiddenBook
        try await bookshelf.upsert(row)
        return row
    }

    private func edit(_ change: (inout Book) -> Void) async {
        guard book != nil, !isSaving, !isLoading else { return }
        isSaving = true; userError = nil
        defer { isSaving = false }
        do {
            let row = try await storedBook()
            var updated = try DiscoveryStorage.book(row)
            change(&updated)
            try await bookshelf.upsert(DiscoveryStorage.row(updated, defaults: row))
            book = updated
        } catch { userError = error.presentation(operation: "保存书籍设置", subject: book?.name) }
    }

    func toggleBookshelf() async {
        guard let book, !isLoading, !isSaving, let url = book.bookUrl, !url.isEmpty else { return }
        isSaving = true
        userError = nil
        defer { isSaving = false }
        do {
            let saved = try await bookshelf.get(bookUrl: url)
            var row = try saved ?? DiscoveryStorage.row(book, defaults: BookRow())
            if saved == nil, let matching = try await DiscoveryStorage.matchingBook(book, in: bookshelf) {
                row = DiscoveryStorage.preservingReading(matching, in: row)
            }
            let wasVisible = saved.map { $0.type & DiscoveryStorage.hiddenBook == 0 } ?? false
            if wasVisible {
                row.type |= DiscoveryStorage.hiddenBook
                try await bookshelf.upsert(row)
            } else {
                row.type &= ~DiscoveryStorage.hiddenBook
                row = try await bookshelf.saveAtTop(row)
            }
            self.book = try DiscoveryStorage.book(row)
            isOnBookshelf = !wasVisible
        } catch { userError = error.presentation(operation: "加入或移出书架", subject: book.name) }
    }
}

enum BookDetailActionError: LocalizedError {
    case invalidVariable
    var errorDescription: String? { "书籍变量必须是字符串键值组成的 JSON 对象。" }
}
