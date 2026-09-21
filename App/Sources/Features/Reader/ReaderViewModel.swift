import Foundation
import Observation
import LegadoCore
import GRDB

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
    var manualReplace: () -> Bool = { false }
    var replaceEnableDefault: () -> Bool = { true }
    var chineseConverterType: () -> Int = { 0 }
    private let cacheDirectory: URL
    private var adaptSpecialStyle: Bool
    var prepareLocalBook: (BookRow) async throws -> BookRow = { $0 }
    var synchronizeWebDav: (BookRow, Bool) async throws -> BookProgress? = { _, _ in nil }
    var manualWebDav: (BookRow, Bool) async throws -> BookProgress? = { _, _ in nil }
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
    var availableChapterCount: Int {
        guard var entity else { return chapters.count }
        entity.totalChapterNum = chapters.count
        return entity.simulatedTotalChapterNum(now: Date(timeIntervalSince1970: Double(now()) / 1000))
    }

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
            guard position < availableChapterCount else { throw ReaderError.chapterLocked }
            let chapter = try ReaderEntityBridge.decode(BookChapter.self, row: latest[position])
            let nextURL = position + 1 < latest.count ? latest[position + 1].url : nil
            let cache = cache, client = client, source = source
            let task = Task { try await cache.content(book: entity, chapter: chapter, nextURL: nextURL, source: source, client: client) }
            downloadTask = task
            let cached = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            let rules = try await ReplaceRuleRepository(database: database).list()
            guard let row = try await ChapterRepository(database: database).get(bookUrl: entity.bookUrl ?? "", index: request.index) else {
                throw ReaderError.emptyChapters
            }
            let input = ReaderLayoutInput(book: entity, chapter: try ReaderEntityBridge.decode(BookChapter.self, row: row),
                rawContent: cached.rawContent, rules: rules,
                manualReplace: manualReplace(), replaceEnableDefault: replaceEnableDefault(), chineseConverterType: chineseConverterType(),
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

    func advanceSpread(forward: Bool, columns: Int) async {
        guard columns > 1 else { if forward { await nextPage() } else { await previousPage() }; return }
        guard !isLoading, let pagination else { return }
        if forward {
            if pageIndex + columns < pagination.pages.count { await selectPage(pageIndex + columns) }
            else { await nextChapter() }
        } else if pageIndex >= columns { await selectPage(pageIndex - columns) }
        else if chapterPosition > 0 {
            await goToChapter(chapters[chapterPosition - 1].index, lastPage: true)
            await selectPage(pageIndex / columns * columns)
        }
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
        guard chapterPosition + 1 < availableChapterCount else { return }
        await goToChapter(chapters[chapterPosition + 1].index)
    }

    func previousChapter() async {
        guard chapterPosition > 0 else { return }
        await goToChapter(chapters[chapterPosition - 1].index)
    }

    private func observeReplaceRules() {
        rulesTask?.cancel()
        let values = ReplaceRuleRepository(database: database).observeAll()
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
            input.rules = try await ReplaceRuleRepository(database: database).list()
            guard token == generation, layoutToken == layoutGeneration else { return }
            if let entity { input.book = entity }
            input.adaptSpecialStyle = adaptSpecialStyle
            input.chineseConverterType = chineseConverterType()
            input.manualReplace = manualReplace()
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
        guard count > 0, let entity, chapterPosition + 1 < availableChapterCount else { return }
        let position = chapterPosition + 1
        let row = chapters[position], nextURL = position + 1 < chapters.count ? chapters[position + 1].url : nil
        let cache = cache, source = source, client = client, token = generation
        let database = database, size = size, settings = settings
        let replaceEnabled = replaceEnableDefault(), converterType = chineseConverterType(), manual = manualReplace()
        let adaptStyle = adaptSpecialStyle, directory = cacheDirectory
        let following = Array(chapters.prefix(availableChapterCount).dropFirst(position + 1).prefix(max(0, count - 1)))
        let chapterRows = chapters
        prefetchTask = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let chapter = try ReaderEntityBridge.decode(BookChapter.self, row: row)
                let cached = try await cache.content(book: entity, chapter: chapter, nextURL: nextURL, source: source, client: client)
                let rules = try await ReplaceRuleRepository(database: database).list()
                let input = ReaderLayoutInput(book: entity, chapter: chapter, rawContent: cached.rawContent, rules: rules,
                    manualReplace: manual, replaceEnableDefault: replaceEnabled, chineseConverterType: converterType,
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
        value.layoutTitleLength = pagination.titleLength
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

    var readerBook: Book? { entity }
    var readerSource: BookSource? { source }
    var rawContent: String { layoutInput?.rawContent ?? "" }
    var currentChapterURL: String { chapters.first(where: { $0.index == chapterIndex })?.url ?? "" }

    func applyBehavior(_ configuration: ReaderBehaviorConfiguration) async {
        configuration.save()
        adaptSpecialStyle = configuration.boolean("adaptSpecialStyle")
        await cache.updateSpecialStyle(adaptSpecialStyle)
        var updated = ReaderSettings.load()
        updated.isEInk = settings.isEInk
        await reflow(settings: updated)
    }

    func updateReadConfig(_ change: @escaping @Sendable (inout ReadConfig) -> Void) async {
        guard let book else { return }
        let token = generation
        do {
            let url = book.bookUrl
            let saved = try await database.write { db in
                guard var row = try BookRow.fetchOne(db, key: url) else { throw ReaderError.missingBook }
                var config = try ReaderEntityBridge.decode(Book.self, row: row).readConfig ?? ReadConfig()
                change(&config)
                row.readConfig = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
                try row.update(db)
                return row
            }
            guard token == generation else { return }
            self.book = saved; entity = try ReaderEntityBridge.decode(Book.self, row: saved)
            if chapterPosition >= availableChapterCount {
                if availableChapterCount > 0 { await goToChapter(chapters[availableChapterCount - 1].index) }
                else { errorMessage = ReaderError.chapterLocked.localizedDescription }
                return
            }
            errorMessage = nil
            await reflow()
        } catch { errorMessage = error.localizedDescription }
    }

    func editContent(_ text: String) async {
        guard let entity, var input = layoutInput else { return }
        let token = generation
        do {
            try BookHelp.save(text, directory: cacheDirectory, book: entity, chapter: input.chapter)
            guard token == generation else { return }
            input.rawContent = text; layoutInput = input; errorMessage = nil
            await reflow()
        } catch { errorMessage = error.localizedDescription }
    }

    func toggleBookmark() async {
        guard let pagination, pagination.pages.indices.contains(pageIndex) else { return }
        let range = pagination.pages[pageIndex].range
        if let bookmark = bookmarks.first(where: { $0.chapterIndex == chapterIndex && NSLocationInRange($0.chapterPos, range) }) {
            await deleteBookmark(bookmark)
        } else { await addBookmark() }
    }

    func toggleRemoveSameTitle() async {
        guard let entity, let input = layoutInput else { return }
        do {
            let enabled = BookHelp.removeSameTitle(directory: cacheDirectory, book: entity, chapter: input.chapter)
            try BookHelp.setRemoveSameTitle(!enabled, directory: cacheDirectory, book: entity, chapter: input.chapter)
            await reflow()
        } catch { errorMessage = error.localizedDescription }
    }

    func reverseContent() async {
        guard let entity, let input = layoutInput else { return }
        do {
            if try BookHelp.content(directory: cacheDirectory, book: entity, chapter: input.chapter) == nil {
                try BookHelp.save(input.rawContent, directory: cacheDirectory, book: entity, chapter: input.chapter)
            }
            if let reversed = try BookHelp.reverseContent(directory: cacheDirectory, book: entity, chapter: input.chapter) { await editContent(reversed) }
        } catch { errorMessage = error.localizedDescription }
    }

    func requestCloudProgress(overwrite: Bool) async {
        guard let book, !synchronizingWebDav else { return }
        let token = generation
        synchronizingWebDav = true
        defer {
            synchronizingWebDav = false
            let waiters = webDavWaiters; webDavWaiters = []
            for waiter in waiters { waiter.resume() }
        }
        do {
            await saveProgress()
            guard let current = try await BookshelfRepository(database: database).get(bookUrl: book.bookUrl) else { return }
            let progress = try await manualWebDav(current, overwrite)
            if token == generation, !closedWebDav {
                pendingWebDavProgress = progress
                if !overwrite && progress == nil { errorMessage = "云端没有这本书的阅读进度。" }
            }
        } catch { if token == generation { errorMessage = error.localizedDescription } }
    }

    func refreshContent() async {
        if let entity, LocalBook.isLocal(entity) {
            let position = chapterIndex, offset = characterOffset, token = beginRequest()
            await cache.cancelPending()
            do {
                try BookHelp.clearCache(directory: cacheDirectory, book: entity,
                    chapters: chapters.map { try ReaderEntityBridge.decode(BookChapter.self, row: $0) })
                await openChapter(ChapterRequest(index: position, offset: offset), token: token)
            } catch { errorMessage = error.localizedDescription; isLoading = false }
            return
        }
        guard let entity, let source, let input = layoutInput else { await retry(); return }
        let token = generation
        do {
            let next = chapters.dropFirst(chapterPosition + 1).first?.url
            let result = try await WebBook(source: source, client: client,
                configuration: .init(adaptSpecialStyle: adaptSpecialStyle))
                .content(book: entity, chapter: input.chapter, nextChapterUrl: next, includeTitle: false)
            guard token == generation else { return }
            await editContent(result.rawContent)
        } catch { errorMessage = error.localizedDescription }
    }

    func openSearchResult(_ result: ReaderSearchMatch) async {
        guard chapters.contains(where: { $0.index == result.chapterIndex }) else { return }
        let token = beginRequest()
        await openChapter(ChapterRequest(index: result.chapterIndex, offset: result.offset), token: token)
    }

    func directoryPresentation() async throws -> (chapters: [BookChapterRow], nodes: [LocalBookTocNode]) {
        guard let entity else { return ([], []) }
        let rows = chapters
        let rules = try await ReplaceRuleRepository(database: database).list()
        let converter = chineseConverterType(), replace = replaceEnableDefault(), manual = manualReplace()
        let task = Task.detached {
            let processor = ContentProcessor(rules: try rules.map { try ReaderEntityBridge.decode(ReplaceRule.self, row: $0) },
                chineseConverterType: converter, replaceEnableDefault: replace, manualReplace: manual)
            let chapters = try rows.map { row in
                try Task.checkCancellation()
                var row = row
                row.title = try processor.title(book: entity, chapter: ReaderEntityBridge.decode(BookChapter.self, row: row))
                return row
            }
            let nodes = try LocalBook.tocNodes(book: entity).map { node in
                var chapter = BookChapter(); chapter.title = node.title; chapter.url = node.href
                return LocalBookTocNode(id: node.id, parentId: node.parentId, depth: node.depth,
                    title: try processor.title(book: entity, chapter: chapter), href: node.href, pageIndex: node.pageIndex)
            }
            return (chapters, nodes)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func openTocEntry(_ entry: ReaderTocEntry) async {
        guard let chapter = entry.chapterIndex else { return }
        await goToChapter(chapter)
        if let page = entry.pageIndex, let index = pagination?.pages.firstIndex(where: { Int(URL(string: $0.imageURL ?? "")?.lastPathComponent ?? "") == page }) {
            await selectPage(index)
        }
    }

    func rebuildLocalDirectory(charset: String? = nil, rule: TxtTocRule? = nil, automatic: Bool = false) async {
        guard var updated = entity, LocalBook.isLocal(updated), let url = updated.bookUrl else { return }
        await saveProgress()
        let token = beginRequest(), position = chapterIndex, oldChapters = chapters
        await cache.cancelPending()
        isLoading = true; errorMessage = nil
        if let charset { updated.charset = charset }
        if automatic { updated.tocUrl = "" }
        else if let rule { updated.tocUrl = rule.persistedValue }
        do {
            let rules = try await TxtTocRuleRepository(database: database).list(enabledOnly: true)
            let input = updated
            let task = Task.detached {
                var book = input
                let chapters = try LocalBook.chapterList(book: &book, rules: rules.isEmpty ? TxtTocRule.builtIn : rules)
                return (book, chapters)
            }
            let (book, parsed) = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard token == generation, !Task.isCancelled else { return }
            guard !parsed.isEmpty else { throw ReaderError.emptyChapters }
            try BookHelp.clearCache(directory: cacheDirectory, book: book,
                chapters: oldChapters.map { try ReaderEntityBridge.decode(BookChapter.self, row: $0) })
            try await LocalBook.save(book: book, chapters: parsed, database: database)
            guard token == generation else { return }
            await load(bookURL: url, chapterIndex: min(position, parsed.count - 1))
        } catch {
            guard token == generation else { return }
            isLoading = false; errorMessage = error.localizedDescription
        }
    }

    func loadChapterWordCounts(progress: (Int, Int) -> Void) async throws {
        guard let entity else { return }
        let token = generation, chapters = chapters
        for (position, row) in chapters.enumerated() {
            try Task.checkCancellation()
            guard token == generation else { throw CancellationError() }
            let chapter = try ReaderEntityBridge.decode(BookChapter.self, row: row)
            let cached = try await cache.content(book: entity, chapter: chapter, nextURL: chapters.dropFirst(position + 1).first?.url, source: source, client: client)
            try Task.checkCancellation()
            let count = String(cached.rawContent.utf16.count)
            try await database.write { db in
                try db.execute(sql: "UPDATE chapters SET wordCount = ? WHERE bookUrl = ? AND url = ? AND \"index\" = ?",
                    arguments: [count, row.bookUrl, row.url, row.index])
            }
            guard token == generation else { throw CancellationError() }
            if let index = self.chapters.firstIndex(where: { $0.index == row.index && $0.url == row.url }) { self.chapters[index].wordCount = count }
            progress(position + 1, chapters.count)
        }
        await refreshCacheStatus()
    }

    func searchText(_ query: String, progress: (Int, Int) -> Void) async throws -> [ReaderSearchMatch] {
        guard let entity, !query.isEmpty else { return [] }
        let token = generation, chapters = chapters
        let rules = try await ReplaceRuleRepository(database: database).list()
        var matches: [ReaderSearchMatch] = []
        for (position, row) in chapters.enumerated() {
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            let chapter = try ReaderEntityBridge.decode(BookChapter.self, row: row)
            let cached = try await cache.content(book: entity, chapter: chapter, nextURL: chapters.dropFirst(position + 1).first?.url, source: source, client: client)
            let input = ReaderLayoutInput(book: entity, chapter: chapter, rawContent: cached.rawContent, rules: rules,
                manualReplace: manualReplace(), replaceEnableDefault: replaceEnableDefault(), chineseConverterType: chineseConverterType(),
                adaptSpecialStyle: adaptSpecialStyle, cacheDirectory: cacheDirectory)
            let settings = settings, size = size
            let rendered = try await Task.detached { try ReaderLayout.build(input: input, size: size, settings: settings, didStart: {}) }.value
            try Task.checkCancellation()
            let text = rendered.pagination.text.string as NSString
            var start = 0
            while start < text.length, matches.count < 1000 {
                let range = text.range(of: query, options: .caseInsensitive, range: NSRange(location: start, length: text.length - start))
                guard range.location != NSNotFound else { break }
                let left = max(0, range.location - 24), right = min(text.length, NSMaxRange(range) + 48)
                let snippetRange = text.rangeOfComposedCharacterSequences(for: NSRange(location: left, length: right - left))
                matches.append(ReaderSearchMatch(chapterIndex: row.index, offset: range.location, title: row.title,
                                                  snippet: text.substring(with: snippetRange)))
                start = NSMaxRange(range)
            }
            progress(position + 1, chapters.count)
            if matches.count >= 1000 { break }
        }
        return matches
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

struct ReaderSearchMatch: Identifiable, Equatable {
    let chapterIndex: Int
    let offset: Int
    let title: String
    let snippet: String
    var id: String { "\(chapterIndex):\(offset)" }
}
