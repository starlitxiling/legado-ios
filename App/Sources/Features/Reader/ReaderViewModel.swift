import Foundation
import Observation
import LegadoCore

struct ReaderDestination: Hashable {
    let bookURL: String
    var chapterIndex: Int? = nil
}

@Observable
@MainActor
final class ReaderViewModel {
    private struct ChapterRequest {
        let index: Int
        let offset: Int
    }

    private(set) var book: BookRow?
    private(set) var chapters: [BookChapterRow] = []
    private(set) var bookmarks: [BookmarkRow] = []
    private(set) var pagination: ReaderPagination?
    private(set) var chapterIndex = 0
    private(set) var pageIndex = 0
    private(set) var chapterTitle = ""
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var prefetchErrorMessage: String?
    private(set) var settings: ReaderSettings
    private(set) var characterOffset = 0
    private var size = CGSize(width: 320, height: 480)
    private var layoutInput: ReaderLayoutInput?
    private var entity: Book?
    private var source: BookSource?
    private let database: AppDatabase
    private let client: any HttpClient
    private let cache: ReaderChapterCache
    private let now: () -> Int64
    private let layoutDidStart: @Sendable () -> Void
    private let waitForLayoutDebounce: @Sendable () async throws -> Void
    private var generation = UUID()
    private var layoutGeneration = UUID()
    private var downloadTask: Task<CachedReaderChapter, Error>?
    private var layoutTask: Task<ReaderLayoutResult, Error>?
    private var prefetchTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var failedRequest: ChapterRequest?
    private var loadDestination: ReaderDestination?

    init(database: AppDatabase, client: any HttpClient, cacheDirectory: URL,
         settings: ReaderSettings = ReaderSettings(),
         now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
         layoutDidStart: @escaping @Sendable () -> Void = {},
         waitForLayoutDebounce: @escaping @Sendable () async throws -> Void = {
             try await Task.sleep(nanoseconds: 80_000_000)
         }) {
        self.database = database; self.client = client
        cache = ReaderChapterCache(directory: cacheDirectory)
        self.settings = settings.normalized; self.now = now
        self.layoutDidStart = layoutDidStart
        self.waitForLayoutDebounce = waitForLayoutDebounce
    }

    var chapterPosition: Int { chapters.firstIndex(where: { $0.index == chapterIndex }) ?? 0 }

    private func beginRequest() -> UUID {
        generation = UUID(); layoutGeneration = UUID()
        downloadTask?.cancel(); prefetchTask?.cancel(); layoutTask?.cancel()
        return generation
    }

    func load(bookURL: String, chapterIndex requestedIndex: Int? = nil) async {
        let token = beginRequest()
        loadDestination = ReaderDestination(bookURL: bookURL, chapterIndex: requestedIndex)
        failedRequest = nil
        isLoading = true; errorMessage = nil
        pagination = nil; layoutInput = nil; book = nil; chapters = []; bookmarks = []
        do {
            guard let book = try await BookshelfRepository(database: database).get(bookUrl: bookURL) else { throw ReaderError.missingBook }
            let chapters = try await ChapterRepository(database: database).list(bookUrl: bookURL)
            guard !chapters.isEmpty else { throw ReaderError.emptyChapters }
            let entity = try ReaderEntityBridge.decode(Book.self, row: book)
            let sourceRow = try await BookSourceRepository(database: database).get(bookSourceUrl: book.origin)
            let source = try sourceRow.map { try ReaderEntityBridge.decode(BookSource.self, row: $0) }
            let bookmarks = try await BookmarkRepository(database: database).list(bookName: book.name, bookAuthor: book.author)
            guard generation == token else { return }
            self.book = book; self.chapters = chapters; self.entity = entity; self.source = source; self.bookmarks = bookmarks
            let desired = requestedIndex ?? book.durChapterIndex
            let index = chapters.first(where: { $0.index == desired })?.index ?? chapters[0].index
            await openChapter(ChapterRequest(index: index, offset: requestedIndex == nil ? book.durChapterPos : 0), token: token)
        } catch {
            guard generation == token else { return }
            errorMessage = error.localizedDescription; isLoading = false
        }
    }

    private func openChapter(_ request: ChapterRequest, token: UUID) async {
        guard let entity else { return }
        isLoading = true; errorMessage = nil; failedRequest = request
        do {
            let latest = try await ChapterRepository(database: database).list(bookUrl: entity.bookUrl ?? "")
            guard let position = latest.firstIndex(where: { $0.index == request.index }) else { throw ReaderError.emptyChapters }
            guard token == generation else { return }
            chapters = latest
            let chapter = try ReaderEntityBridge.decode(BookChapter.self, row: latest[position])
            let nextURL = position + 1 < latest.count ? latest[position + 1].url : nil
            let cache = cache, client = client, source = source
            let task = Task { try await cache.content(book: entity, chapter: chapter, nextURL: nextURL, source: source, client: client) }
            downloadTask = task
            let cached = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            let rules = try await ReplaceRuleRepository(database: database).list(enabled: true)
            guard let row = try await ChapterRepository(database: database).get(bookUrl: entity.bookUrl ?? "", index: request.index) else {
                throw ReaderError.emptyChapters
            }
            let input = ReaderLayoutInput(book: entity, chapter: try ReaderEntityBridge.decode(BookChapter.self, row: row),
                rawContent: cached.rawContent, rules: rules)
            while token == generation {
                let layoutToken = UUID(); layoutGeneration = layoutToken
                do {
                    let result = try await render(input: input, debounce: true)
                    guard token == generation, layoutToken == layoutGeneration else { continue }
                    try Task.checkCancellation()
                    layoutInput = input; chapterIndex = request.index; chapterTitle = result.title
                    pagination = result.pagination
                    pageIndex = result.pagination.pageIndex(at: request.offset)
                    characterOffset = request.offset == Int.max ? result.pagination.firstCharacterOffset(on: pageIndex) :
                        max(0, min(request.offset, max(0, result.pagination.text.length - 1)))
                    failedRequest = nil; isLoading = false
                    await saveProgress()
                    guard token == generation else { return }
                    prefetchNextChapter()
                    return
                } catch is CancellationError {
                    if Task.isCancelled || token != generation { return }
                }
            }
        } catch {
            guard token == generation else { return }
            errorMessage = error.localizedDescription; isLoading = false
        }
    }

    private func render(input: ReaderLayoutInput, debounce: Bool) async throws -> ReaderLayoutResult {
        layoutTask?.cancel()
        let size = size, settings = settings, didStart = layoutDidStart, waitForDebounce = waitForLayoutDebounce
        let task = Task.detached(priority: .userInitiated) {
            if debounce { try await waitForDebounce() }
            return try ReaderLayout.build(input: input, size: size, settings: settings, didStart: didStart)
        }
        layoutTask = task
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func goToChapter(_ index: Int, lastPage: Bool = false) async {
        guard chapters.contains(where: { $0.index == index }) else { return }
        let token = beginRequest()
        await openChapter(ChapterRequest(index: index, offset: lastPage ? Int.max : 0), token: token)
    }

    func retry() async {
        if let failedRequest {
            let token = beginRequest()
            await openChapter(failedRequest, token: token)
        } else if let loadDestination {
            await load(bookURL: loadDestination.bookURL, chapterIndex: loadDestination.chapterIndex)
        }
    }

    func nextPage() async {
        guard !isLoading, let pagination else { return }
        if pageIndex + 1 < pagination.pages.count { await selectPage(pageIndex + 1) }
        else { await nextChapter() }
    }

    func previousPage() async {
        guard !isLoading else { return }
        if pageIndex > 0 { await selectPage(pageIndex - 1) }
        else if chapterPosition > 0 { await goToChapter(chapters[chapterPosition - 1].index, lastPage: true) }
    }

    func selectPage(_ index: Int) async {
        guard !isLoading, let pagination, pagination.pages.indices.contains(index) else { return }
        pageIndex = index
        characterOffset = pagination.firstCharacterOffset(on: index)
        await saveProgress()
    }

    func nextChapter() async {
        guard chapterPosition + 1 < chapters.count else { return }
        await goToChapter(chapters[chapterPosition + 1].index)
    }

    func previousChapter() async {
        guard chapterPosition > 0 else { return }
        await goToChapter(chapters[chapterPosition - 1].index)
    }

    func reflow(size: CGSize? = nil, settings: ReaderSettings? = nil) async {
        if let size { self.size = size }
        if let settings { self.settings = settings.normalized }
        let token = generation, layoutToken = UUID()
        layoutGeneration = layoutToken; layoutTask?.cancel()
        guard !isLoading, let input = layoutInput else { return }
        do {
            let result = try await render(input: input, debounce: settings != nil)
            guard token == generation, layoutToken == layoutGeneration else { return }
            pagination = result.pagination; pageIndex = result.pagination.pageIndex(at: characterOffset)
            chapterTitle = result.title
            await saveProgress()
        } catch is CancellationError {
        } catch {
            guard token == generation, layoutToken == layoutGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    func saveProgress() async {
        guard let book, pagination != nil else { return }
        let index = chapterIndex, offset = characterOffset, title = chapterTitle, time = now()
        let previous = saveTask
        let repository = BookshelfRepository(database: database)
        let task = Task { [weak self] in
            await previous?.value
            do {
                let saved = try await repository.updateProgress(bookUrl: book.bookUrl, chapterIndex: index,
                    chapterPos: offset, chapterTitle: title, readTime: time)
                if !saved { throw ReaderError.missingBook }
            } catch { self?.errorMessage = error.localizedDescription }
        }
        saveTask = task
        await task.value
    }

    private func prefetchNextChapter() {
        prefetchTask?.cancel(); prefetchErrorMessage = nil
        guard let entity, chapterPosition + 1 < chapters.count else { return }
        let position = chapterPosition + 1
        let row = chapters[position], nextURL = position + 1 < chapters.count ? chapters[position + 1].url : nil
        let cache = cache, source = source, client = client, token = generation
        prefetchTask = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let chapter = try ReaderEntityBridge.decode(BookChapter.self, row: row)
                _ = try await cache.content(book: entity, chapter: chapter, nextURL: nextURL, source: source, client: client)
            } catch {
                guard !Task.isCancelled, self?.generation == token else { return }
                self?.prefetchErrorMessage = error.localizedDescription
            }
        }
    }

    func waitForPrefetch() async { await prefetchTask?.value }

    func close() async {
        _ = beginRequest(); isLoading = false
        await cache.cancelPending()
        await saveProgress()
    }
}
