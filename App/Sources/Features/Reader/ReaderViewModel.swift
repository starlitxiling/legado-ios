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
    private(set) var highlights: [BookHighlight] = []
    private(set) var cachedChapterIndices: Set<Int> = []
    private(set) var pagination: ReaderPagination?
    private(set) var nextChapterPagination: ReaderPagination?
    private var previewGeneration = UUID()

    var nextPagePreview: (pagination: ReaderPagination, index: Int, currentChapter: Bool)? {
        guard let pagination else { return nil }
        if pagination.pages.indices.contains(pageIndex + 1) { return (pagination, pageIndex + 1, true) }
        return nextChapterPagination.map { ($0, 0, false) }
    }
    private(set) var chapterIndex = 0
    private(set) var pageIndex = 0
    private(set) var chapterTitle = ""
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var prefetchErrorMessage: String?
    private(set) var settings: ReaderSettings
    private(set) var characterOffset = 0
    private(set) var readAloudRange: NSRange?

    func followReadAloud(chapter: Int, range: NSRange, offset: Int? = nil) {
        guard chapter == chapterIndex, let pagination, !isLoading else { return }
        readAloudRange = range
        let position = min(max(0, offset ?? range.location), max(0, pagination.text.length - 1))
        guard characterOffset != position else { return }
        characterOffset = position
        pageIndex = pagination.pageIndex(at: position)
        Task { await saveProgress() }
    }

    func clearReadAloudHighlight() { readAloudRange = nil }
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
    private var chapterUpdateTask: Task<Void, Never>?
    private var rulesTask: Task<Void, Never>?
    private var pendingRulesRefresh = false
    private let preDownloadCount: @Sendable () -> Int
    var replaceEnableDefault: () -> Bool = { true }
    var chineseConverterType: () -> Int = { 0 }
    private let cacheDirectory: URL
    private let adaptSpecialStyle: Bool
    var prepareLocalBook: (BookRow) async throws -> BookRow = { $0 }
    var synchronizeWebDav: (BookRow, Bool) async throws -> BookProgress? = { _, _ in nil }
    var pendingWebDavProgress: BookProgress?
    private(set) var closedWebDav = false
    private var synchronizingWebDav = false
    private var webDavWaiters: [CheckedContinuation<Void, Never>] = []
    private var saveTask: Task<Void, Never>?
    private var failedRequest: ChapterRequest?
    private var loadDestination: ReaderDestination?

    init(database: AppDatabase, client: any HttpClient, cacheDirectory: URL,
         settings: ReaderSettings = ReaderSettings(), threadCount: Int = 32, adaptSpecialStyle: Bool = true,
         preDownloadCount: @escaping @Sendable () -> Int = { 1 },
         now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
         layoutDidStart: @escaping @Sendable () -> Void = {},
         waitForLayoutDebounce: @escaping @Sendable () async throws -> Void = {
             try await Task.sleep(nanoseconds: 80_000_000)
         }) {
        self.database = database; self.client = client
        self.cacheDirectory = cacheDirectory; self.adaptSpecialStyle = adaptSpecialStyle
        self.preDownloadCount = preDownloadCount
        cache = ReaderChapterCache(directory: cacheDirectory, threadCount: threadCount, adaptSpecialStyle: adaptSpecialStyle)
        self.settings = settings.normalized; self.now = now
        self.layoutDidStart = layoutDidStart
        self.waitForLayoutDebounce = waitForLayoutDebounce
    }

    var chapterPosition: Int { chapters.firstIndex(where: { $0.index == chapterIndex }) ?? 0 }

    private func beginRequest() -> UUID {
        previewGeneration = UUID(); nextChapterPagination = nil
        generation = UUID(); layoutGeneration = UUID()
        downloadTask?.cancel(); prefetchTask?.cancel(); layoutTask?.cancel()
        chapterUpdateTask?.cancel(); chapterUpdateTask = nil
        return generation
    }

    func load(bookURL: String, chapterIndex requestedIndex: Int? = nil) async {
        rulesTask?.cancel(); rulesTask = nil; pendingRulesRefresh = false
        closedWebDav = false
        pendingWebDavProgress = nil
        let token = beginRequest()
        loadDestination = ReaderDestination(bookURL: bookURL, chapterIndex: requestedIndex)
        failedRequest = nil
        isLoading = true; errorMessage = nil
        pagination = nil; layoutInput = nil; book = nil; chapters = []; bookmarks = []
        highlights = []; cachedChapterIndices = []
        do {
            guard let stored = try await BookshelfRepository(database: database).get(bookUrl: bookURL) else { throw ReaderError.missingBook }
            var book = try await prepareLocalBook(stored)
            if book.variable != stored.variable {
                try await database.write { db in
                    try db.execute(sql: "UPDATE books SET variable = ? WHERE bookUrl = ? AND variable IS ?", arguments: [book.variable, stored.bookUrl, stored.variable])
                }
            }
            var entity = try ReaderEntityBridge.decode(Book.self, row: book)
            let sourceRow = try await BookSourceRepository(database: database).get(bookSourceUrl: book.origin)
            let source = try sourceRow.map { try ReaderEntityBridge.decode(BookSource.self, row: $0) }
            let repository = ChapterRepository(database: database)
            var chapters = try await repository.list(bookUrl: bookURL)
            if LocalBook.isLocal(entity), try chapters.isEmpty || LocalBook.isModified(entity) {
                let rules = try await TxtTocRuleRepository(database: database).list(enabledOnly: true)
                let input = entity
                let parsing = Task.detached(priority: .userInitiated) {
                    var updated = input
                    let chapters = try LocalBook.chapterList(book: &updated, rules: rules)
                    return (updated, chapters)
                }
                let (updated, parsed) = try await withTaskCancellationHandler { try await parsing.value } onCancel: { parsing.cancel() }
                let restored = try parsed.map { try ReaderEntityBridge.decode(BookChapterRow.self, row: $0) }
                guard generation == token, !Task.isCancelled else { return }
                book = try await LocalBook.save(book: updated, chapters: parsed, database: database)
                entity = try ReaderEntityBridge.decode(Book.self, row: book)
                chapters = restored
            }
            if chapters.isEmpty, !LocalBook.isLocal(entity) {
                guard let source else { throw ReaderError.missingSource }
                let parsed = try await WebBook(source: source, client: client).chapterList(book: &entity)
                let restored = try parsed.map { try ReaderEntityBridge.decode(BookChapterRow.self, row: $0) }
                try Task.checkCancellation()
                guard generation == token else { return }
                try await BookshelfRepository(database: database).saveChapterUpdate(
                    bookURL: bookURL, chapters: restored, checkedAt: entity.lastCheckTime)
                guard let refreshed = try await BookshelfRepository(database: database).get(bookUrl: bookURL) else {
                    throw ReaderError.missingBook
                }
                book = refreshed
                entity = try ReaderEntityBridge.decode(Book.self, row: refreshed)
                chapters = restored
            }
            guard !chapters.isEmpty else { throw ReaderError.emptyChapters }
            let bookmarks = try await BookmarkRepository(database: database).list(bookName: book.name, bookAuthor: book.author)
            guard generation == token else { return }
            self.book = book; self.chapters = chapters; self.entity = entity; self.source = source; self.bookmarks = bookmarks
            let desired = requestedIndex ?? book.durChapterIndex
            let index = chapters.first(where: { $0.index == desired })?.index ?? chapters[0].index
            await openChapter(ChapterRequest(index: index, offset: requestedIndex == nil ? book.durChapterPos : 0), token: token)
            if generation == token { observeReplaceRules() }
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
                rawContent: cached.rawContent, rules: rules,
                replaceEnableDefault: replaceEnableDefault(), chineseConverterType: chineseConverterType(),
                adaptSpecialStyle: adaptSpecialStyle, cacheDirectory: cacheDirectory)
            while token == generation {
                let layoutToken = UUID(); layoutGeneration = layoutToken
                do {
                    let result = try await render(input: input, debounce: true)
                    guard token == generation, layoutToken == layoutGeneration else { continue }
                    try Task.checkCancellation()
                    if chapterIndex != request.index { highlights = [] }
                    layoutInput = input; chapterIndex = request.index; chapterTitle = result.title
                    pagination = result.pagination
                    pageIndex = result.pagination.pageIndex(at: request.offset)
                    characterOffset = request.offset == Int.max ? result.pagination.firstCharacterOffset(on: pageIndex) :
                        max(0, min(request.offset, max(0, result.pagination.text.length - 1)))
                    failedRequest = nil; isLoading = false
                    await saveProgress()
                    guard token == generation else { return }
                    if pendingRulesRefresh {
                        pendingRulesRefresh = false
                        await reflow()
                    } else { prefetchNextChapter() }
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

    private func observeReplaceRules() {
        rulesTask?.cancel()
        let values = ReplaceRuleRepository(database: database).observeEnabled()
        rulesTask = Task { [weak self] in
            do {
                for try await rules in values {
                    try Task.checkCancellation()
                    guard let self else { return }
                    if self.isLoading { self.pendingRulesRefresh = true }
                    else if let current = self.layoutInput, current.rules != rules { await self.reflow() }
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self?.errorMessage = error.localizedDescription }
            }
        }
    }

    func reflow(size: CGSize? = nil, settings: ReaderSettings? = nil) async {
        previewGeneration = UUID(); nextChapterPagination = nil; prefetchTask?.cancel()
        if let size { self.size = size }
        if let settings { self.settings = settings.normalized }
        let token = generation, layoutToken = UUID()
        layoutGeneration = layoutToken; layoutTask?.cancel()
        guard !isLoading, var input = layoutInput else { return }
        do {
            input.rules = try await ReplaceRuleRepository(database: database).list(enabled: true)
            guard token == generation, layoutToken == layoutGeneration else { return }
            input.chineseConverterType = chineseConverterType()
            input.replaceEnableDefault = replaceEnableDefault()
            layoutInput = input
            let result = try await render(input: input, debounce: settings != nil)
            guard token == generation, layoutToken == layoutGeneration else { return }
            layoutInput = input
            pagination = result.pagination; pageIndex = result.pagination.pageIndex(at: characterOffset)
            chapterTitle = result.title
            prefetchNextChapter()
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
        let previewToken = UUID(); previewGeneration = previewToken; nextChapterPagination = nil
        let count = min(100, max(0, preDownloadCount()))
        if count > 0 { scheduleChapterUpdate() }
        guard count > 0, let entity, chapterPosition + 1 < chapters.count else { return }
        let position = chapterPosition + 1
        let row = chapters[position], nextURL = position + 1 < chapters.count ? chapters[position + 1].url : nil
        let cache = cache, source = source, client = client, token = generation
        let database = database, size = size, settings = settings
        let replaceEnabled = replaceEnableDefault(), converterType = chineseConverterType()
        let adaptStyle = adaptSpecialStyle, directory = cacheDirectory
        let following = Array(chapters.dropFirst(position + 1).prefix(max(0, count - 1)))
        let chapterRows = chapters
        prefetchTask = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let chapter = try ReaderEntityBridge.decode(BookChapter.self, row: row)
                let cached = try await cache.content(book: entity, chapter: chapter, nextURL: nextURL, source: source, client: client)
                let rules = try await ReplaceRuleRepository(database: database).list(enabled: true)
                let input = ReaderLayoutInput(book: entity, chapter: chapter, rawContent: cached.rawContent, rules: rules,
                    replaceEnableDefault: replaceEnabled, chineseConverterType: converterType,
                    adaptSpecialStyle: adaptStyle, cacheDirectory: directory)
                let layout = Task.detached {
                    try ReaderLayout.build(input: input, size: size, settings: settings, didStart: {})
                }
                let result = try await withTaskCancellationHandler { try await layout.value } onCancel: { layout.cancel() }
                guard !Task.isCancelled, self?.generation == token, self?.previewGeneration == previewToken else { return }
                self?.nextChapterPagination = result.pagination
                for row in following {
                    try Task.checkCancellation()
                    let chapter = try ReaderEntityBridge.decode(BookChapter.self, row: row)
                    let next = chapterRows.firstIndex(where: { $0.url == row.url }).flatMap { $0 + 1 < chapterRows.count ? chapterRows[$0 + 1].url : nil }
                    _ = try await cache.content(book: entity, chapter: chapter, nextURL: next, source: source, client: client)
                }
            } catch {
                guard !Task.isCancelled, self?.generation == token else { return }
                self?.prefetchErrorMessage = error.localizedDescription
            }
        }
    }

    private func scheduleChapterUpdate() {
        guard chapterUpdateTask == nil, let entity, let source, entity.canUpdate,
              !LocalBook.isLocal(entity), chapters.count - chapterPosition - 1 < 3 else { return }
        let token = generation, timestamp = now()
        chapterUpdateTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == token { chapterUpdateTask = nil } }
            do {
                let repository = BookshelfRepository(database: database)
                guard try await repository.claimChapterUpdate(bookURL: entity.bookUrl ?? "", now: timestamp) else { return }
                var updated = entity
                updated.lastCheckTime = timestamp
                if generation == token { self.entity?.lastCheckTime = timestamp; book?.lastCheckTime = timestamp }
                let oldCount = chapters.count
                let parsed = try await WebBook(source: source, client: client, now: { timestamp })
                    .chapterList(book: &updated, runPreUpdate: true)
                try Task.checkCancellation()
                guard generation == token, parsed.count > oldCount else { return }
                let rows = try parsed.map { try ReaderEntityBridge.decode(BookChapterRow.self, row: $0) }
                let saved = try await SourceChangeTransaction.save(book: updated, previous: entity, chapters: rows, database: database)
                guard generation == token else { return }
                self.entity = saved
                book = try ReaderEntityBridge.decode(BookRow.self, row: saved)
                chapters = try await ChapterRepository(database: database).list(bookUrl: saved.bookUrl ?? "")
                prefetchNextChapter()
            } catch {
                if generation == token, !Task.isCancelled { prefetchErrorMessage = error.localizedDescription }
            }
        }
    }

    func waitForChapterUpdates() async { await chapterUpdateTask?.value }

    func waitForPrefetch() async { await prefetchTask?.value }

    func refreshCacheStatus() async {
        guard let entity else { return }
        var indices: Set<Int> = []
        for row in chapters {
            guard let chapter = try? ReaderEntityBridge.decode(BookChapter.self, row: row) else { continue }
            if await cache.hasContent(book: entity, chapter: chapter) { indices.insert(row.index) }
        }
        guard book?.bookUrl == entity.bookUrl else { return }
        cachedChapterIndices = indices
    }

    var supportsReviews: Bool { source?.ruleReview?.enabled == true }

    func reviews(paragraph: Int) async throws -> [ReaderReviewItem] {
        guard let entity, let source, let input = layoutInput else { return [] }
        let review = BookReview(source: source, client: client)
        let summary = try await review.summary(book: entity, chapter: input.chapter)
        return try await review.details(book: entity, chapter: input.chapter, paragraphIndex: paragraph,
            paragraphData: summary.keys[paragraph] ?? String(paragraph))
    }

    func refreshHighlights() async {
        guard let book else { return }
        let index = chapterIndex
        do {
            let result = try await BookHighlightRepository(database: database).list(bookURL: book.bookUrl, chapterIndex: index)
            guard self.book?.bookUrl == book.bookUrl, chapterIndex == index else { return }
            highlights = result
        } catch { errorMessage = error.localizedDescription }
    }

    func addHighlight(range: NSRange, note: String) async {
        guard let book, let pagination, range.location >= 0, range.length > 0,
              range.location <= pagination.text.length, range.length <= pagination.text.length - range.location else { return }
        var value = BookHighlight()
        value.time = max(now(), (highlights.map(\.time).max() ?? 0) + 1)
        value.bookUrl = book.bookUrl; value.bookName = book.name; value.bookAuthor = book.author
        value.chapterIndex = chapterIndex; value.chapterUrl = chapters.first(where: { $0.index == chapterIndex })?.url ?? ""
        value.chapterName = chapterTitle; value.chapterPos = range.location; value.chapterPosEnd = NSMaxRange(range)
        value.layoutTitleLength = settings.titleMode == 2 ? 0 : (chapterTitle as NSString).length + 1
        value.bookText = pagination.text.attributedSubstring(from: range).string; value.note = note
        do { try await BookHighlightRepository(database: database).upsert(value); await refreshHighlights() }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteHighlight(_ value: BookHighlight) async {
        do { try await BookHighlightRepository(database: database).delete(value); await refreshHighlights() }
        catch { errorMessage = error.localizedDescription }
    }

    func addBookmark() async {
        guard let book, let pagination else { return }
        var value = BookmarkRow()
        value.time = max(now(), (bookmarks.map(\.time).max() ?? 0) + 1)
        value.bookName = book.name; value.bookAuthor = book.author
        value.chapterIndex = chapterIndex; value.chapterPos = characterOffset; value.chapterName = chapterTitle
        if pagination.pages.indices.contains(pageIndex) { value.bookText = pagination.pages[pageIndex].text.string }
        do {
            try await BookmarkRepository(database: database).upsert(value)
            bookmarks = try await BookmarkRepository(database: database).list(bookName: book.name, bookAuthor: book.author)
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteBookmark(_ value: BookmarkRow) async {
        do { try await BookmarkRepository(database: database).delete(value); bookmarks.removeAll { $0.time == value.time } }
        catch { errorMessage = error.localizedDescription }
    }

    func openBookmark(_ value: BookmarkRow) async {
        guard chapters.contains(where: { $0.index == value.chapterIndex }) else { return }
        let token = beginRequest()
        await openChapter(ChapterRequest(index: value.chapterIndex, offset: value.chapterPos), token: token)
    }

    func close() async {
        rulesTask?.cancel(); rulesTask = nil
        _ = beginRequest(); isLoading = false
        await cache.cancelPending()
        await saveProgress()
        if !closedWebDav {
            closedWebDav = true
            await syncWebDavProgress(exiting: true)
        }
    }

    func syncWebDavProgress(exiting: Bool = false) async {
        if exiting, synchronizingWebDav {
            await withCheckedContinuation { webDavWaiters.append($0) }
        }
        guard exiting || !closedWebDav, !synchronizingWebDav, !isLoading,
              let book, book.type & DiscoveryStorage.hiddenBook == 0 else { return }
        let token = generation
        synchronizingWebDav = true
        defer {
            synchronizingWebDav = false
            let waiters = webDavWaiters
            webDavWaiters = []
            for waiter in waiters { waiter.resume() }
        }
        do {
            await saveProgress()
            guard let current = try await BookshelfRepository(database: database).get(bookUrl: book.bookUrl) else { return }
            let progress = try await synchronizeWebDav(current, exiting)
            if !exiting, !closedWebDav, token == generation { pendingWebDavProgress = progress }
        } catch { errorMessage = error.localizedDescription }
    }

    func acceptWebDavProgress(_ progress: BookProgress) async {
        pendingWebDavProgress = nil
        guard chapters.contains(where: { $0.index == progress.durChapterIndex }) else { return }
        let token = beginRequest()
        await openChapter(ChapterRequest(index: progress.durChapterIndex, offset: progress.durChapterPos), token: token)
    }
}
