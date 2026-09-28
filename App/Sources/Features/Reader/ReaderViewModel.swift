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
    private(set) var previousChapterPagination: ReaderPagination?
    private(set) var lastTurnForward = true
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
    private(set) var userError: UserFacingError?
    var errorMessage: String? { userError?.displayText }
    private(set) var prefetchError: UserFacingError?
    var prefetchErrorMessage: String? { prefetchError?.displayText }
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
        scheduleProgressSave()
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
    private var previousPreviewTask: Task<Void, Never>?
    private var chapterUpdateTask: Task<Void, Never>?
    private var rulesTask: Task<Void, Never>?
    private var pendingRulesRefresh = false
    private let preDownloadCount: @Sendable () -> Int
    var autoChangeSource: () -> Bool = { false }
    private(set) var recoveringMessage: String?
    private(set) var isPlaceholder = false
    @ObservationIgnored private(set) var sourceRecoveryTask: Task<Void, Never>?
    private var recoveryGeneration = UUID()
    var acceptsInput: Bool { !isLoading && book != nil }
    private let sourceConcurrency: Int
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
    @ObservationIgnored private var progressSaveTask: Task<Void, Never>?
    private let waitForProgressSave: @Sendable () async throws -> Void
    private var failedRequest: ChapterRequest?
    private var loadDestination: ReaderDestination?

    init(database: AppDatabase, client: any HttpClient, cacheDirectory: URL,
         settings: ReaderSettings = ReaderSettings(), threadCount: Int = 32, adaptSpecialStyle: Bool = true,
         preDownloadCount: @escaping @Sendable () -> Int = { 1 },
         now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
         layoutDidStart: @escaping @Sendable () -> Void = {},
         waitForLayoutDebounce: @escaping @Sendable () async throws -> Void = {
             try await Task.sleep(nanoseconds: 80_000_000)
         }, waitForProgressSave: @escaping @Sendable () async throws -> Void = {
             try await Task.sleep(for: .milliseconds(250))
         }) {
        self.database = database; self.client = client
        self.cacheDirectory = cacheDirectory; self.adaptSpecialStyle = adaptSpecialStyle
        self.preDownloadCount = preDownloadCount
        sourceConcurrency = threadCount
        cache = ReaderChapterCache(directory: cacheDirectory, threadCount: threadCount, adaptSpecialStyle: adaptSpecialStyle)
        self.settings = settings.normalized; self.now = now
        self.layoutDidStart = layoutDidStart
        self.waitForLayoutDebounce = waitForLayoutDebounce
        self.waitForProgressSave = waitForProgressSave
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
        downloadTask?.cancel(); prefetchTask?.cancel(); previousPreviewTask?.cancel(); layoutTask?.cancel(); cancelSourceRecovery()
        chapterUpdateTask?.cancel(); chapterUpdateTask = nil
        return generation
    }

    func load(bookURL: String, chapterIndex requestedIndex: Int? = nil) async {
        previousChapterPagination = nil
        rulesTask?.cancel(); rulesTask = nil; pendingRulesRefresh = false
        closedWebDav = false
        pendingWebDavProgress = nil
        let token = beginRequest()
        await saveProgress()
        guard generation == token, !Task.isCancelled else { return }
        loadDestination = ReaderDestination(bookURL: bookURL, chapterIndex: requestedIndex)
        failedRequest = nil
        isLoading = true; userError = nil; isPlaceholder = false
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
            if chapters.isEmpty, !LocalBook.isLocal(entity), let source {
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
            if chapters.isEmpty, source == nil, !LocalBook.isLocal(entity) {
                var placeholder = BookChapterRow()
                placeholder.bookUrl = bookURL; placeholder.url = bookURL + "#missing-source"
                placeholder.index = requestedIndex ?? book.durChapterIndex
                placeholder.title = book.durChapterTitle ?? "没有书源"
                chapters = [placeholder]
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
            guard generation == token, !Task.isCancelled else { return }
            report(error, operation: "打开书籍", actions: [.retry, .changeSource, .manageSources, .back]); isLoading = false
            if !error.isCancellation { await startSourceRecovery(bookURL: bookURL, index: requestedIndex, token: token) }
        }
    }

    func dismissError() { userError = nil }

    private func report(_ error: Error, operation: String, chapter: String? = nil,
                        actions: [UserFacingError.Action] = []) {
        guard !error.isCancellation else { return }
        let subject = [book?.name ?? loadDestination?.bookURL, chapter ?? chapterTitle, source?.bookSourceName]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        AppLogStore.shared.append("\(operation): \(String(reflecting: error))")
        userError = error.presentation(operation: operation, subject: subject, actions: actions)
    }

    private func reportPrefetch(_ error: Error, operation: String) {
        guard !error.isCancellation else { return }
        AppLogStore.shared.append("\(operation): \(String(reflecting: error))")
        prefetchError = error.presentation(operation: operation, subject: book?.name)
    }

    func cancelSourceRecovery() {
        recoveryGeneration = UUID()
        sourceRecoveryTask?.cancel(); sourceRecoveryTask = nil; recoveringMessage = nil
    }

    private func startSourceRecovery(bookURL: String, index: Int?, token: UUID) async {
        guard autoChangeSource(), sourceRecoveryTask == nil, token == generation else { return }
        do {
            guard let row = try await BookshelfRepository(database: database).get(bookUrl: bookURL),
                  !LocalBook.isLocal(try ReaderEntityBridge.decode(Book.self, row: row)),
                  try await BookSourceRepository(database: database).get(bookSourceUrl: row.origin) == nil,
                  token == generation, !Task.isCancelled else { return }
        } catch {
            report(error, operation: "查找书源", actions: [.changeSource, .manageSources])
            return
        }
        let recovery = UUID(); recoveryGeneration = recovery
        recoveringMessage = "正在自动换源…"
        sourceRecoveryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if recoveryGeneration == recovery { recoveringMessage = nil; sourceRecoveryTask = nil }
            }
            do {
                guard let row = try await BookshelfRepository(database: database).get(bookUrl: bookURL) else { return }
                let previous = try ReaderEntityBridge.decode(Book.self, row: row)
                guard !LocalBook.isLocal(previous) else { return }
                let rows = try await BookSourceRepository(database: database).list(enabled: true)
                let sources = try rows.filter { $0.bookSourceType == 0 && $0.bookSourceUrl != row.origin }
                    .map { try ReaderEntityBridge.decode(BookSource.self, row: $0) }
                try Task.checkCancellation()
                guard token == generation else { return }
                let configuration = WebBookConfiguration(cacheDirectory: cacheDirectory, threadCount: sourceConcurrency, adaptSpecialStyle: adaptSpecialStyle)
                let requested = index ?? row.durChapterIndex
                let title = chapters.first { $0.index == requested }?.title ?? row.durChapterTitle ?? ""
                let candidate = try await ReaderSourceRecovery.find(book: previous, chapterIndex: requested,
                    chapterTitle: title, sources: sources, client: client, configuration: configuration)
                try Task.checkCancellation()
                guard token == generation else { return }
                let chapterRows = try candidate.chapters.map { try DiscoveryStorage.row($0, defaults: BookChapterRow()) }
                let saved = try await SourceChangeTransaction.save(book: candidate.book, previous: previous, chapters: chapterRows, database: database)
                try Task.checkCancellation()
                guard token == generation, let url = saved.bookUrl else { return }
                sourceRecoveryTask = nil; recoveringMessage = nil
                await load(bookURL: url, chapterIndex: candidate.index)
            } catch {
                guard token == generation, !Task.isCancelled, !error.isCancellation else { return }
                report(error, operation: "自动换源", actions: [.retry, .changeSource, .manageSources, .back])
            }
        }
    }

    private func showMissingSource(_ request: ChapterRequest, token: UUID) async {
        guard let entity, let row = chapters.first(where: { $0.index == request.index }) else { return }
        do {
            let chapter = try ReaderEntityBridge.decode(BookChapter.self, row: row)
            let input = ReaderLayoutInput(book: entity, chapter: chapter,
                rawContent: "加载正文失败\n没有书源", rules: [], sourceImageStyle: nil,
                replaceEnableDefault: false)
            let layoutToken = UUID(); layoutGeneration = layoutToken
            layoutInput = input; chapterIndex = request.index; characterOffset = 0; isPlaceholder = true
            let result = try await render(input: input, debounce: false)
            guard token == generation, layoutToken == layoutGeneration, !Task.isCancelled else { return }
            chapterTitle = result.title; pagination = result.pagination; pageIndex = 0
        } catch {
            guard token == generation, !error.isCancellation else { return }
            AppLogStore.shared.append("Missing-source placeholder: \(String(reflecting: error))")
        }
    }

    private func openChapter(_ request: ChapterRequest, token: UUID) async {
        guard let entity else { return }
        isLoading = true; userError = nil; failedRequest = request
        do {
            let stored = try await ChapterRepository(database: database).list(bookUrl: entity.bookUrl ?? "")
            let latest = stored.isEmpty && source == nil && !LocalBook.isLocal(entity) ? chapters : stored
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
            let highlightRules = try await HighlightRuleRepository(database: database).all()
            guard let row = try await ChapterRepository(database: database).get(bookUrl: entity.bookUrl ?? "", index: request.index) else {
                throw ReaderError.emptyChapters
            }
            let input = ReaderLayoutInput(book: entity, chapter: try ReaderEntityBridge.decode(BookChapter.self, row: row),
                rawContent: cached.rawContent, rules: rules, highlightRules: highlightRules, sourceImageStyle: source?.ruleContent?.imageStyle,
                manualReplace: manualReplace(), replaceEnableDefault: replaceEnableDefault(), chineseConverterType: chineseConverterType(),
                adaptSpecialStyle: adaptSpecialStyle, cacheDirectory: cacheDirectory)
            while token == generation {
                let layoutToken = UUID(); layoutGeneration = layoutToken
                do {
                    let result = try await render(input: input, debounce: true)
                    guard token == generation, layoutToken == layoutGeneration else { continue }
                    try Task.checkCancellation()
                    if chapterIndex != request.index {
                        previousChapterPagination = position > 0 && latest[position - 1].index == chapterIndex ? pagination : nil
                        lastTurnForward = request.index > chapterIndex
                        highlights = []
                    }
                    layoutInput = input; chapterIndex = request.index; chapterTitle = result.title
                    pagination = result.pagination
                    pageIndex = result.pagination.pageIndex(at: request.offset)
                    characterOffset = request.offset == Int.max ? result.pagination.firstCharacterOffset(on: pageIndex) :
                        max(0, min(request.offset, max(0, result.pagination.text.length - 1)))
                    failedRequest = nil; isLoading = false; isPlaceholder = false
                    await saveProgress()
                    guard token == generation else { return }
                    if pendingRulesRefresh {
                        pendingRulesRefresh = false
                        let latestRules = try await ReplaceRuleRepository(database: database).list()
                        guard token == generation else { return }
                        if latestRules != input.rules { await reflow() }
                        else { prefetchNextChapter() }
                    } else { prefetchNextChapter() }
                    return
                } catch is CancellationError {
                    if Task.isCancelled || token != generation { return }
                }
            }
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            report(error, operation: "正文加载", chapter: chapters.first { $0.index == request.index }?.title, actions: [.retry, .changeSource, .manageSources, .back]); isLoading = false
            if (error as? ReaderError) == .missingSource { await showMissingSource(request, token: token) }
            if !error.isCancellation, (error as? ReaderError) != .chapterLocked {
                await startSourceRecovery(bookURL: entity.bookUrl ?? "", index: request.index, token: token)
            }
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
        lastTurnForward = index >= pageIndex
        pageIndex = index
        characterOffset = pagination.firstCharacterOffset(on: index)
        scheduleProgressSave()
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
                if !Task.isCancelled { self?.report(error, operation: "监听替换规则", actions: []) }
            }
        }
    }

    func reflow(size: CGSize? = nil, settings: ReaderSettings? = nil) async {
        previewGeneration = UUID(); nextChapterPagination = nil; previousChapterPagination = nil; prefetchTask?.cancel(); previousPreviewTask?.cancel()
        if let size { self.size = size }
        if let settings { self.settings = settings.normalized }
        let token = generation, layoutToken = UUID()
        layoutGeneration = layoutToken; layoutTask?.cancel()
        guard !isLoading, var input = layoutInput else { return }
        do {
            input.rules = isPlaceholder ? [] : try await ReplaceRuleRepository(database: database).list()
            input.highlightRules = isPlaceholder ? [] : try await HighlightRuleRepository(database: database).all()
            guard token == generation, layoutToken == layoutGeneration else { return }
            if let entity { input.book = entity }
            input.sourceImageStyle = source?.ruleContent?.imageStyle
            input.adaptSpecialStyle = adaptSpecialStyle
            input.chineseConverterType = chineseConverterType()
            input.manualReplace = manualReplace()
            input.replaceEnableDefault = !isPlaceholder && replaceEnableDefault()
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
            report(error, operation: "正文排版", actions: [])
        }
    }

    private func scheduleProgressSave() {
        progressSaveTask?.cancel()
        let wait = waitForProgressSave
        progressSaveTask = Task { [weak self] in
            do { try await wait(); try Task.checkCancellation() }
            catch { return }
            self?.progressSaveTask = nil
            await self?.saveProgress()
        }
    }

    func saveProgress() async {
        progressSaveTask?.cancel(); progressSaveTask = nil
        guard let book, pagination != nil, !isPlaceholder else { return }
        let index = chapterIndex, offset = characterOffset, title = chapterTitle, time = now()
        let previous = saveTask
        let repository = BookshelfRepository(database: database)
        let task = Task { [weak self] in
            await previous?.value
            do {
                let saved = try await repository.updateProgress(bookUrl: book.bookUrl, chapterIndex: index,
                    chapterPos: offset, chapterTitle: title, readTime: time)
                if !saved { throw ReaderError.missingBook }
            } catch { self?.report(error, operation: "保存阅读进度", actions: []) }
        }
        saveTask = task
        await task.value
    }

    private func preparePreviousPreview() {
        previousPreviewTask?.cancel()
        guard !isPlaceholder, previousChapterPagination == nil, chapterPosition > 0, let entity else { return }
        let row = chapters[chapterPosition - 1], nextURL = chapters[chapterPosition].url
        let token = generation, layoutToken = layoutGeneration
        let cache = cache, client = client, database = database, size = size, settings = settings
        let source = source, downloadAllowed = preDownloadCount() > 0
        let manual = manualReplace(), replaceEnabled = replaceEnableDefault(), converter = chineseConverterType()
        let adapt = adaptSpecialStyle, directory = cacheDirectory
        previousPreviewTask = Task { [weak self] in
            do {
                let chapter = try ReaderEntityBridge.decode(BookChapter.self, row: row)
                if !downloadAllowed && !LocalBook.isLocal(entity) {
                    guard await cache.hasContent(book: entity, chapter: chapter) else { return }
                }
                let cached = try await cache.content(book: entity, chapter: chapter, nextURL: nextURL,
                    source: downloadAllowed ? source : nil, client: client)
                let rules = try await ReplaceRuleRepository(database: database).list()
                let highlights = try await HighlightRuleRepository(database: database).all()
                let input = ReaderLayoutInput(book: entity, chapter: chapter, rawContent: cached.rawContent,
                    rules: rules, highlightRules: highlights, sourceImageStyle: source?.ruleContent?.imageStyle,
                    manualReplace: manual, replaceEnableDefault: replaceEnabled, chineseConverterType: converter,
                    adaptSpecialStyle: adapt, cacheDirectory: directory)
                let layout = Task.detached { try ReaderLayout.build(input: input, size: size, settings: settings, didStart: {}) }
                let result = try await withTaskCancellationHandler { try await layout.value } onCancel: { layout.cancel() }
                guard !Task.isCancelled, self?.generation == token, self?.layoutGeneration == layoutToken else { return }
                self?.previousChapterPagination = result.pagination
            } catch {
                guard !error.isCancellation, !Task.isCancelled, self?.generation == token else { return }
                self?.reportPrefetch(error, operation: "预览上一章")
            }
        }
    }

    private func prefetchNextChapter() {
        preparePreviousPreview()
        prefetchTask?.cancel(); prefetchError = nil
        let previewToken = UUID(); previewGeneration = previewToken; nextChapterPagination = nil
        let count = min(100, max(0, preDownloadCount()))
        guard !isPlaceholder else { return }
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
                let highlightRules = try await HighlightRuleRepository(database: database).all()
                let input = ReaderLayoutInput(book: entity, chapter: chapter, rawContent: cached.rawContent, rules: rules, highlightRules: highlightRules, sourceImageStyle: source?.ruleContent?.imageStyle,
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
                self?.reportPrefetch(error, operation: "预加载正文")
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
                if generation == token, !Task.isCancelled { reportPrefetch(error, operation: "自动刷新目录") }
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
        } catch { report(error, operation: "读取批注", actions: []) }
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
        catch { report(error, operation: "保存批注", actions: []) }
    }

    func deleteHighlight(_ value: BookHighlight) async {
        do { try await BookHighlightRepository(database: database).delete(value); await refreshHighlights() }
        catch { report(error, operation: "删除批注", actions: []) }
    }

    func addBookmark(selection: NSRange? = nil, note: String = "") async {
        guard let book, let pagination else { return }
        var value = BookmarkRow()
        value.time = max(now(), (bookmarks.map(\.time).max() ?? 0) + 1)
        value.bookName = book.name; value.bookAuthor = book.author
        value.chapterIndex = chapterIndex; value.chapterPos = characterOffset; value.chapterName = chapterTitle
        value.content = note
        if let selection {
            guard selection.location >= 0, selection.length > 0, NSMaxRange(selection) <= pagination.text.length else { return }
            value.chapterPos = selection.location; value.bookText = pagination.text.attributedSubstring(from: selection).string
        } else if pagination.pages.indices.contains(pageIndex) { value.bookText = pagination.pages[pageIndex].text.string }
        do {
            try await BookmarkRepository(database: database).upsert(value)
            bookmarks = try await BookmarkRepository(database: database).list(bookName: book.name, bookAuthor: book.author)
        } catch { report(error, operation: "添加书签", actions: []) }
    }

    func deleteBookmark(_ value: BookmarkRow) async {
        do { try await BookmarkRepository(database: database).delete(value); bookmarks.removeAll { $0.time == value.time } }
        catch { report(error, operation: "删除书签", actions: []) }
    }

    func openBookmark(_ value: BookmarkRow) async {
        guard chapters.contains(where: { $0.index == value.chapterIndex }) else { return }
        let token = beginRequest()
        await openChapter(ChapterRequest(index: value.chapterIndex, offset: value.chapterPos), token: token)
    }

    var readerBook: Book? { entity }
    var readerSource: BookSource? { source }
    var readerChapter: BookChapter? { layoutInput?.chapter }

    func reloadSource() async {
        guard let book, !LocalBook.isLocal(entity ?? Book()) else { return }
        let token = generation
        do {
            guard let row = try await BookSourceRepository(database: database).get(bookSourceUrl: book.origin) else { throw ReaderError.missingSource }
            guard token == generation else { return }
            source = try ReaderEntityBridge.decode(BookSource.self, row: row)
        } catch { report(error, operation: "重新加载书源", actions: [.manageSources]) }
    }
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
                else { report(ReaderError.chapterLocked, operation: "打开章节") }
                return
            }
            userError = nil
            await reflow()
        } catch { report(error, operation: "保存阅读设置", actions: []) }
    }

    func editContent(_ text: String) async {
        guard let entity, var input = layoutInput else { return }
        let token = generation
        do {
            try BookHelp.save(text, directory: cacheDirectory, book: entity, chapter: input.chapter)
            guard token == generation else { return }
            input.rawContent = text; layoutInput = input; userError = nil
            await reflow()
        } catch { report(error, operation: "保存正文修改", actions: []) }
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
        } catch { report(error, operation: "切换同名标题过滤", actions: []) }
    }

    func reverseContent() async {
        guard let entity, let input = layoutInput else { return }
        do {
            if try BookHelp.content(directory: cacheDirectory, book: entity, chapter: input.chapter) == nil {
                try BookHelp.save(input.rawContent, directory: cacheDirectory, book: entity, chapter: input.chapter)
            }
            if let reversed = try BookHelp.reverseContent(directory: cacheDirectory, book: entity, chapter: input.chapter) { await editContent(reversed) }
        } catch { report(error, operation: "反转正文", actions: []) }
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
                if !overwrite && progress == nil { userError = UserFacingError(title: "云端进度", message: "\(book.name)：云端没有这本书的阅读进度。") }
            }
        } catch { if token == generation { report(error, operation: "同步云端进度", actions: []) } }
    }

    private var scriptRefreshActive = false
    func refreshFromScript(_ event: String) async {
        guard !scriptRefreshActive, !isLoading, let current = entity, let source, !LocalBook.isLocal(current) else { return }
        scriptRefreshActive = true
        defer { scriptRefreshActive = false }
        if event == "refreshContent" { await refreshContent(); return }
        let token = generation
        do {
            let web = WebBook(source: source, client: client)
            var updated = current
            var rows = chapters
            if event == "refreshBookInfo" { updated = try await web.bookInfo(current) }
            else if event == "refreshBookToc" {
                rows = try await web.chapterList(book: &updated).map { try ReaderEntityBridge.decode(BookChapterRow.self, row: $0) }
                guard !rows.isEmpty else { throw ReaderError.emptyChapters }
            } else { return }
            guard generation == token else { return }
            let saved = try await SourceChangeTransaction.save(book: updated, previous: current, chapters: rows, database: database)
            guard generation == token else { return }
            entity = saved; book = try ReaderEntityBridge.decode(BookRow.self, row: saved)
            chapters = try await ChapterRepository(database: database).list(bookUrl: saved.bookUrl ?? "")
        } catch { if generation == token { report(error, operation: "刷新书籍信息或目录", actions: [.manageSources]) } }
    }

    func refreshContent() async {
        if let entity, LocalBook.isLocal(entity) {
            let position = chapterIndex, offset = characterOffset, token = beginRequest()
            await cache.cancelPending()
            do {
                try BookHelp.clearCache(directory: cacheDirectory, book: entity,
                    chapters: chapters.map { try ReaderEntityBridge.decode(BookChapter.self, row: $0) })
                await openChapter(ChapterRequest(index: position, offset: offset), token: token)
            } catch { report(error, operation: "刷新正文", actions: [.retry, .changeSource]); isLoading = false }
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
        } catch { report(error, operation: "刷新正文", actions: [.retry, .changeSource]) }
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
        isLoading = true; userError = nil
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
            isLoading = false; report(error, operation: "重建本地目录", actions: [])
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
        let highlightRules = try await HighlightRuleRepository(database: database).all()
        var matches: [ReaderSearchMatch] = []
        for (position, row) in chapters.enumerated() {
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            let chapter = try ReaderEntityBridge.decode(BookChapter.self, row: row)
            let cached = try await cache.content(book: entity, chapter: chapter, nextURL: chapters.dropFirst(position + 1).first?.url, source: source, client: client)
            let input = ReaderLayoutInput(book: entity, chapter: chapter, rawContent: cached.rawContent, rules: rules, highlightRules: highlightRules, sourceImageStyle: source?.ruleContent?.imageStyle,
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
        } catch { report(error, operation: "同步阅读进度", actions: []) }
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
