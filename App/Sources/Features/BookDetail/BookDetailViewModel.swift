import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class BookDetailViewModel {
    let results: [SearchBook]
    private(set) var selectedSourceIndex = 0
    private(set) var book: Book?
    private(set) var source: BookSource?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isOnBookshelf = false
    private(set) var errorMessage: String?

    private let sources: BookSourceRepository
    private let bookshelf: BookshelfRepository
    private let client: any HttpClient
    private var generation = 0

    init(results: [SearchBook], sources: BookSourceRepository,
         bookshelf: BookshelfRepository, client: any HttpClient) {
        self.results = results
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
        errorMessage = nil
        defer { if request == generation { isLoading = false } }
        do {
            guard let row = try await sources.get(bookSourceUrl: result.origin ?? "") else {
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
            book = loaded
            source = selected
            isOnBookshelf = saved.map { $0.type & DiscoveryStorage.hiddenBook == 0 } ?? false
        } catch {
            if request == generation, !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    func refreshShelfState() async {
        guard let url = book?.bookUrl else { return }
        do {
            let saved = try await bookshelf.get(bookUrl: url)
            guard book?.bookUrl == url else { return }
            isOnBookshelf = saved.map { $0.type & DiscoveryStorage.hiddenBook == 0 } ?? false
        } catch { errorMessage = error.localizedDescription }
    }

    func toggleBookshelf() async {
        guard let book, !isLoading, !isSaving, let url = book.bookUrl, !url.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let saved = try await bookshelf.get(bookUrl: url)
            var row = try saved ?? DiscoveryStorage.row(book, defaults: BookRow())
            if saved == nil, let matching = try await DiscoveryStorage.matchingBook(book, in: bookshelf) {
                row = DiscoveryStorage.preservingReading(matching, in: row)
            }
            let wasVisible = saved.map { $0.type & DiscoveryStorage.hiddenBook == 0 } ?? false
            if wasVisible { row.type |= DiscoveryStorage.hiddenBook }
            else { row.type &= ~DiscoveryStorage.hiddenBook }
            if saved == nil { try await bookshelf.replaceByIdentity([row]) }
            else { try await bookshelf.upsert(row) }
            self.book = try DiscoveryStorage.book(row)
            isOnBookshelf = !wasVisible
        } catch { errorMessage = error.localizedDescription }
    }
}
