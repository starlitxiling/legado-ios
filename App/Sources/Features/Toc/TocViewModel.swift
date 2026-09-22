import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class TocViewModel {
    private(set) var book: Book
    private(set) var chapters: [BookChapterRow] = []
    private(set) var cachedChapterIndices: Set<Int> = []
    private(set) var isLoading = false
    private(set) var userError: UserFacingError?
    var errorMessage: String? { userError?.displayText }
    func dismissError() { userError = nil }
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
            refreshCacheStatus()
        } catch {
            if !error.isCancellation { AppLogStore.shared.append("Read directory: \(String(reflecting: error))") }
            userError = error.presentation(operation: "读取目录", subject: book.name, actions: [.retry])
        }
    }

    func refresh() async {
        guard !isLoading, let url = book.bookUrl, !url.isEmpty else { return }
        isLoading = true
        userError = nil
        defer { isLoading = false }
        do {
            var updated = book
            let countWords = UserDefaults.standard.object(forKey: "tocCountWords") as? Bool ?? false
            let previous = countWords ? try chapters.map { try JSONDecoder().decode(BookChapter.self, from: JSONEncoder().encode($0)) } : []
            let loaded = try await WebBook(source: source, client: client, tocCountWords: countWords,
                configuration: .init(threadCount: UserDefaults.standard.object(forKey: "threadCount") as? Int ?? 32))
                .chapterList(book: &updated, previousChapters: previous, runPreUpdate: true)
            try Task.checkCancellation()
            let rows = try loaded.map { try DiscoveryStorage.row($0, defaults: BookChapterRow()) }
            updated = try await SourceChangeTransaction.save(book: updated, previous: book, chapters: rows, database: database)
            chapters = rows
            book = updated
            refreshCacheStatus()
        } catch {
            if !error.isCancellation { AppLogStore.shared.append("Refresh directory: \(String(reflecting: error))") }
            if !Task.isCancelled { userError = error.presentation(operation: "刷新目录", subject: [book.name, source.bookSourceName].compactMap { $0 }.joined(separator: " · "), actions: [.retry]) }
        }
    }

    private func refreshCacheStatus() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Legado/ReaderCache", isDirectory: true)
        cachedChapterIndices = Set(chapters.compactMap { row in
            guard let data = try? JSONEncoder().encode(row),
                  let chapter = try? JSONDecoder().decode(BookChapter.self, from: data),
                  ReaderCacheStatus.hasContent(book: book, chapter: chapter, directory: directory) else { return nil }
            return row.index
        })
    }
}
