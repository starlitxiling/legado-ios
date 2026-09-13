import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class TocViewModel {
    private(set) var book: Book
    private(set) var chapters: [BookChapterRow] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var isReversed = false
    var displayedChapters: [BookChapterRow] { isReversed ? chapters.reversed() : chapters }
    var currentChapterIndex: Int? {
        chapters.first(where: { $0.index == book.durChapterIndex })?.index
    }

    private let source: BookSource
    private let chapterRepository: ChapterRepository
    private let bookshelf: BookshelfRepository
    private let client: any HttpClient
    private let database: AppDatabase

    init(book: Book, source: BookSource, chapters: ChapterRepository,
         bookshelf: BookshelfRepository, client: any HttpClient, database: AppDatabase) {
        self.book = book
        self.source = source
        chapterRepository = chapters
        self.bookshelf = bookshelf
        self.client = client
        self.database = database
    }

    func load() async {
        do {
            chapters = try await chapterRepository.list(bookUrl: book.bookUrl ?? "")
            if chapters.isEmpty { await refresh() }
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh() async {
        guard !isLoading, let url = book.bookUrl, !url.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var updated = book
            let loaded = try await WebBook(source: source, client: client).chapterList(book: &updated)
            try Task.checkCancellation()
            let rows = try loaded.map { try DiscoveryStorage.row($0, defaults: BookChapterRow()) }
            updated = try await SourceChangeTransaction.save(book: updated, previous: book, chapters: rows, database: database)
            chapters = rows
            book = updated
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }
}
