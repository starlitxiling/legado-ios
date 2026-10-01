import Foundation
import Observation
import LegadoCore

enum BookshelfDownloadsError: LocalizedError {
    case missingSource, emptyChapters, invalidRange, missingContent(Int)
    var errorDescription: String? {
        switch self {
        case .missingSource: return "找不到对应书源。"
        case .emptyChapters: return "目录为空，请先更新章节。"
        case .invalidRange: return "章节范围无效。"
        case .missingContent(let index): return "第 \(index + 1) 章未缓存，请先下载所选范围。"
        }
    }
}

@Observable
@MainActor
final class DownloadCenterModel {
    struct BookGroup: Identifiable, Equatable {
        static let visibleQueuedLimit = 30
        let bookURL: String
        let total: Int
        let completed: Int
        let failed: Int
        let running: Int
        let queued: Int
        let paused: Int
        /// Failed and running chapters, then at most `visibleQueuedLimit` of the rest that still need work.
        let visible: [CacheBook.Progress]
        var id: String { bookURL }
        var summary: String { "共 \(total) 章：完成 \(completed)，失败 \(failed)，下载中 \(running)，等待 \(queued)，暂停 \(paused)" }
        var hidden: Int { total - completed - visible.count }

        static func == (lhs: BookGroup, rhs: BookGroup) -> Bool {
            lhs.bookURL == rhs.bookURL && lhs.summary == rhs.summary && lhs.visible.map(\.id) == rhs.visible.map(\.id)
                && lhs.visible.map(\.attempts) == rhs.visible.map(\.attempts) && lhs.visible.map(\.error) == rhs.visible.map(\.error)
        }

        static func make(_ items: [CacheBook.Progress]) -> [BookGroup] {
            var order: [String] = []
            var buckets: [String: [CacheBook.Progress]] = [:]
            for item in items {
                if buckets[item.bookURL] == nil { order.append(item.bookURL) }
                buckets[item.bookURL, default: []].append(item)
            }
            return order.sorted().map { url in
                let items = buckets[url] ?? []
                var counts: [CacheBook.State: Int] = [:]
                for item in items { counts[item.state, default: 0] += 1 }
                let urgent = items.filter { $0.state == .failed || $0.state == .running }
                let rest = items.lazy.filter { $0.state == .queued || $0.state == .paused || $0.state == .cancelled }
                    .prefix(visibleQueuedLimit)
                return BookGroup(bookURL: url, total: items.count, completed: counts[.completed] ?? 0, failed: counts[.failed] ?? 0,
                                 running: counts[.running] ?? 0, queued: counts[.queued] ?? 0, paused: counts[.paused] ?? 0,
                                 visible: urgent + rest)
            }
        }
    }

    private(set) var progress: [CacheBook.Progress] = []
    private(set) var groups: [BookGroup] = []
    private(set) var pauseReasons: [String: String] = [:]
    @ObservationIgnored private var revision = -1
    private(set) var bookNames: [String: String] = [:]
    var userError: UserFacingError?
    var errorMessage: String? { userError?.displayText }
    private(set) var isRefreshing = false
    private(set) var isStoppingRefresh = false
    private(set) var refreshTotal = 0
    private(set) var refreshCompleted = 0
    @ObservationIgnored private var refreshTask: Task<BookshelfRefresh.Report, Error>?
    private(set) var refreshingBookURLs = Set<String>()
    private(set) var refreshReport: BookshelfRefresh.Report?
    let queue: CacheBook
    private let database: AppDatabase
    private let client: any HttpClient
    let directory: URL
    private let threadCount: Int
    private let adaptSpecialStyle: Bool

    init(database: AppDatabase, client: any HttpClient, directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Legado/ReaderCache"), threadCount: Int = 3, adaptSpecialStyle: Bool = true) {
        self.threadCount = threadCount
        self.adaptSpecialStyle = adaptSpecialStyle
        queue = CacheBook(maximumConcurrent: min(128, max(1, threadCount)))
        self.database = database; self.client = client; self.directory = directory
    }

    func clearInvalidCache() async throws -> Int {
        let books = try await BookshelfRepository(database: database).all().map { try DiscoveryStorage.book($0) }
        let directory = directory
        let cleanup = Task.detached(priority: .utility) { try BookHelp.clearInvalidCache(directory: directory, books: books) }
        return try await withTaskCancellationHandler { try await cleanup.value } onCancel: { cleanup.cancel() }
    }

    func poll() async {
        while !Task.isCancelled {
            await refreshSnapshot()
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        }
    }

    func download(_ rows: [BookRow], range: ClosedRange<Int>? = nil) async {
        userError = nil
        for row in rows {
            bookNames[row.bookUrl] = row.name
            do {
                let book = try DiscoveryStorage.book(row)
                let stored = try await ChapterRepository(database: database).list(bookUrl: row.bookUrl)
                let chapters = try stored.map { try JSONDecoder().decode(BookChapter.self, from: JSONEncoder().encode($0)) }
                guard !chapters.isEmpty else { throw BookshelfDownloadsError.emptyChapters }
                if let range, range.lowerBound < 0 || range.upperBound >= chapters.count { throw BookshelfDownloadsError.invalidRange }
                let source: BookSource
                if LocalBook.isLocal(book) { source = BookSource() }
                else {
                    guard let sourceRow = try await BookSourceRepository(database: database).resolveForBookOrigin(row.origin) else { throw BookshelfDownloadsError.missingSource }
                    source = try DiscoveryStorage.source(sourceRow)
                }
                let client = client, directory = directory, threadCount = threadCount, adaptSpecialStyle = adaptSpecialStyle
                let cookies = CookieStore()
                for cookie in try await CookieRepository(database: database).list() { await cookies.setCookie(url: cookie.url, cookie: cookie.cookie) }
                let selected = chapters.filter { range?.contains($0.index) ?? true }
                await queue.enqueue(bookURL: row.bookUrl, chapters: selected.map(\.index)) { index in
                    guard let position = chapters.firstIndex(where: { $0.index == index }) else { throw BookshelfDownloadsError.invalidRange }
                    let chapter = chapters[position]
                    if LocalBook.isLocal(book) {
                        if try BookHelp.content(directory: directory, book: book, chapter: chapter) != nil { return }
                    } else if BookHelp.hasImageContent(directory: directory, book: book, chapter: chapter) { return }
                    let nextURL = position + 1 < chapters.count ? chapters[position + 1].url : nil
                    let result = try await WebBook(source: source, client: client, cookies: cookies,
                        configuration: .init(cacheDirectory: directory, threadCount: threadCount, adaptSpecialStyle: adaptSpecialStyle)).content(
                            book: book, chapter: chapter, nextChapterUrl: nextURL, includeTitle: false)
                    if LocalBook.isLocal(book) {
                        try BookHelp.save(result.rawContent, directory: directory, book: book, chapter: chapter)
                        try await BookHelp.saveImages(source: source, book: book, chapter: chapter, content: result.rawContent,
                            directory: directory, client: client, cookies: cookies)
                    }
                }
            } catch { userError = error.presentation(operation: "缓存书籍", subject: row.name) }
        }
        await refreshSnapshot()
    }

    private func refreshSnapshot() async {
        guard let change = await queue.changes(since: revision) else { return }
        revision = change.revision
        progress = change.progress
        let updated = BookGroup.make(change.progress)
        if updated != groups { groups = updated }
        if change.pauseReasons != pauseReasons { pauseReasons = change.pauseReasons }
    }

    func refresh(_ rows: [BookRow]? = nil, onlyUpdateRead: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true; isStoppingRefresh = false; userError = nil
        refreshReport = nil; refreshTotal = 0; refreshCompleted = 0
        defer { isRefreshing = false; isStoppingRefresh = false; refreshingBookURLs = []; refreshTask = nil }
        let database = database, client = client
        let task = Task {
            try Task.checkCancellation()
            return try await BookshelfRefreshService.refresh(database: database, client: client, rows: rows, onlyUpdateRead: onlyUpdateRead,
                onPrepared: { [weak self] urls in await self?.setRefreshing(urls) },
                onCompleted: { [weak self] url in await self?.finishedRefreshing(url) })
        }
        refreshTask = task
        do {
            refreshReport = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        } catch { userError = error.presentation(operation: "更新书架目录") }
    }

    func stopRefresh() {
        guard isRefreshing else { return }
        isStoppingRefresh = true
        refreshTask?.cancel()
    }

    private func setRefreshing(_ urls: [String]) {
        refreshingBookURLs = Set(urls); refreshTotal = refreshingBookURLs.count
    }
    private func finishedRefreshing(_ url: String) {
        if refreshingBookURLs.remove(url) != nil { refreshCompleted += 1 }
    }

    func export(_ row: BookRow, range: ClosedRange<Int>, epub: Bool, useReplace: Bool) async throws -> URL {
        userError = nil
        let book = try DiscoveryStorage.book(row)
        let stored = try await ChapterRepository(database: database).list(bookUrl: row.bookUrl)
        guard range.lowerBound >= 0, range.upperBound < stored.count else { throw BookshelfDownloadsError.invalidRange }
        var items: [BookExporter.Chapter] = []
        for item in stored where range.contains(item.index) {
            try Task.checkCancellation()
            let chapter = try JSONDecoder().decode(BookChapter.self, from: JSONEncoder().encode(item))
            let content: String
            if chapter.isVolume && (chapter.url ?? "").hasPrefix(chapter.title ?? "") { content = "" }
            else if LocalBook.isLocal(book) { content = try LocalBook.content(book: book, chapter: chapter) }
            else if let cached = try BookHelp.content(directory: directory, book: book, chapter: chapter) { content = cached }
            else { throw BookshelfDownloadsError.missingContent(item.index) }
            items.append(.init(chapter: chapter, content: content))
        }
        let rules = try await ReplaceRuleRepository(database: database).list(enabled: true).map { row -> ReplaceRule in
            var rule = try JSONDecoder().decode(ReplaceRule.self, from: JSONEncoder().encode(row))
            rule.order = row.order
            return rule
        }
        let directory = directory
        let exporter = BookExporter(book: book, chapters: items, rules: rules) { src in
            try BookHelp.imageData(directory: directory, book: book, src: src)
        }
        var cover: BookExporter.Cover?
        if epub, let coverURL = row.customCoverUrl ?? row.coverUrl, !coverURL.isEmpty {
            do {
                let data = try await ImageRepositoryLoader.load(url: coverURL, origin: row.origin, book: book, isCover: true,
                    sources: BookSourceRepository(database: database), cookies: CookieRepository(database: database), client: client,
                    cacheDirectory: directory.appendingPathComponent("ImageCache"))
                let isPNG = data.starts(with: [137, 80, 78, 71])
                guard isPNG || data.starts(with: [255, 216, 255]) else { throw BookExporter.ExportError.unsupportedCover }
                cover = .init(data: data, mediaType: isPNG ? "image/png" : "image/jpeg")
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                userError = error.presentation(operation: "加载导出封面", subject: row.name + "（将继续导出无封面书籍）")
            }
        }
        let data = try epub ? exporter.epub(range: range, useReplace: useReplace, cover: cover)
            : Data(exporter.txt(range: range, useReplace: useReplace).utf8)
        let folder = directory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(BookHelp.folderName(book)).appendingPathExtension(epub ? "epub" : "txt")
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum BookshelfRefreshService {
    static func refresh(database: AppDatabase, client: any HttpClient, rows: [BookRow]? = nil,
                        onlyUpdateRead: Bool = false,
                        onPrepared: @escaping @Sendable ([String]) async -> Void = { _ in },
                        onCompleted: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> BookshelfRefresh.Report {
        let repository = BookshelfRepository(database: database)
        let books: [BookRow]
        if let rows { books = rows }
        else {
            let all = try await repository.list()
            let groups = try await BookGroupRepository(database: database).list()
            let mask = groups.filter { $0.groupId > 0 }.reduce(Int64(0)) { $0 | $1.groupId }
            books = all.filter { book in
                let matching = groups.filter { $0.groupId != -1 && $0.groupId != -100 && BookGroupMembership.contains(book, groupID: $0.groupId, customMask: mask) }
                return matching.isEmpty || matching.contains { $0.enableRefresh && (!$0.onlyUpdateRead || hasFinished(book)) }
            }
        }
        let eligible = books.filter { $0.canUpdate && $0.type & 256 == 0 && $0.origin != "loc_book" && (!onlyUpdateRead || hasFinished($0)) }
        await onPrepared(eligible.map(\.bookUrl))
        return await BookshelfRefresh.run(bookURLs: eligible.map(\.bookUrl)) { url in
            do {
                guard let current = try await repository.get(bookUrl: url) else { throw BookshelfEditError.missingBook }
                guard let sourceRow = try await BookSourceRepository(database: database).resolveForBookOrigin(current.origin) else { throw BookshelfRefresh.UpdateError.missingSource }
                let previousBook = try DiscoveryStorage.book(current)
                var book = previousBook
                let countWords = UserDefaults.standard.object(forKey: "tocCountWords") as? Bool ?? false
                let previous: [BookChapter]
                if countWords {
                    previous = try await ChapterRepository(database: database).list(bookUrl: url).map {
                        try JSONDecoder().decode(BookChapter.self, from: JSONEncoder().encode($0))
                    }
                } else { previous = [] }
                let chapters = try await WebBook(source: DiscoveryStorage.source(sourceRow), client: client, tocCountWords: countWords,
                    configuration: .init(threadCount: UserDefaults.standard.object(forKey: "threadCount") as? Int ?? 32))
                    .chapterList(book: &book, previousChapters: previous, runPreUpdate: true)
                let rows = try chapters.map { try DiscoveryStorage.row($0, defaults: BookChapterRow()) }
                try Task.checkCancellation()
                if book.bookUrl != previousBook.bookUrl || book.tocUrl != previousBook.tocUrl || book.variable != previousBook.variable {
                    _ = try await SourceChangeTransaction.save(book: book, previous: previousBook, chapters: rows, database: database)
                } else { try await repository.saveChapterUpdate(bookURL: url, chapters: rows, checkedAt: book.lastCheckTime) }
                await onCompleted(url)
            } catch {
                await onCompleted(url)
                if !(error is CancellationError) && !Task.isCancelled { try await repository.markUpdateFailed(bookURL: url) }
                throw error
            }
        }
    }

    private static func hasFinished(_ book: BookRow) -> Bool {
        book.totalChapterNum <= 1 || book.durChapterIndex >= book.totalChapterNum - 1
    }
}
