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
    private(set) var progress: [CacheBook.Progress] = []
    private(set) var bookNames: [String: String] = [:]
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    private(set) var refreshReport: BookshelfRefresh.Report?
    let queue: CacheBook
    private let database: AppDatabase
    private let client: any HttpClient
    let directory: URL

    init(database: AppDatabase, client: any HttpClient, directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Legado/ReaderCache"), threadCount: Int = 3) {
        queue = CacheBook(maximumConcurrent: min(128, max(1, threadCount)))
        self.database = database; self.client = client; self.directory = directory
    }

    func poll() async {
        while !Task.isCancelled {
            progress = await queue.snapshot()
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        }
    }

    func download(_ rows: [BookRow], range: ClosedRange<Int>? = nil) async {
        errorMessage = nil
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
                    guard let sourceRow = try await BookSourceRepository(database: database).get(bookSourceUrl: row.origin) else { throw BookshelfDownloadsError.missingSource }
                    source = try DiscoveryStorage.source(sourceRow)
                }
                let client = client, directory = directory
                let cookies = CookieStore()
                for cookie in try await CookieRepository(database: database).list() { await cookies.setCookie(url: cookie.url, cookie: cookie.cookie) }
                let selected = chapters.filter { range?.contains($0.index) ?? true }
                await queue.enqueue(bookURL: row.bookUrl, chapters: selected.map(\.index)) { index in
                    guard let position = chapters.firstIndex(where: { $0.index == index }) else { throw BookshelfDownloadsError.invalidRange }
                    let chapter = chapters[position]
                    if BookHelp.hasImageContent(directory: directory, book: book, chapter: chapter) { return }
                    let nextURL = position + 1 < chapters.count ? chapters[position + 1].url : nil
                    let content: String
                    if let cached = try BookHelp.content(directory: directory, book: book, chapter: chapter) { content = cached }
                    else {
                        let result = try await WebBook(source: source, client: client).content(book: book, chapter: chapter,
                            nextChapterUrl: nextURL, includeTitle: false)
                        content = result.rawContent
                        try BookHelp.save(content, directory: directory, book: book, chapter: chapter)
                    }
                    try await BookHelp.saveImages(source: source, book: book, chapter: chapter, content: content,
                                                  directory: directory, client: client, cookies: cookies)
                }
            } catch { errorMessage = "\(row.name)：\(error.localizedDescription)" }
        }
        progress = await queue.snapshot()
    }

    func refresh(_ rows: [BookRow]? = nil) async {
        guard !isRefreshing else { return }
        isRefreshing = true; errorMessage = nil
        defer { isRefreshing = false }
        do { refreshReport = try await BookshelfRefreshService.refresh(database: database, client: client, rows: rows) }
        catch { errorMessage = error.localizedDescription }
    }

    func export(_ row: BookRow, range: ClosedRange<Int>, epub: Bool, useReplace: Bool) async throws -> URL {
        errorMessage = nil
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
                errorMessage = "封面加载失败，将无封面导出：\(error.localizedDescription)"
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
    static func refresh(database: AppDatabase, client: any HttpClient, rows: [BookRow]? = nil) async throws -> BookshelfRefresh.Report {
        let repository = BookshelfRepository(database: database)
        let books: [BookRow]
        if let rows { books = rows }
        else {
            let all = try await repository.list()
            let groups = try await BookGroupRepository(database: database).list()
            let mask = groups.filter { $0.groupId > 0 }.reduce(Int64(0)) { $0 | $1.groupId }
            books = all.filter { book in
                let matching = groups.filter { $0.groupId != -1 && $0.groupId != -100 && BookGroupMembership.contains(book, groupID: $0.groupId, customMask: mask) }
                return matching.isEmpty || matching.contains { $0.enableRefresh && (!$0.onlyUpdateRead || book.totalChapterNum - book.durChapterIndex - 1 <= 0) }
            }
        }
        let eligible = books.filter { $0.canUpdate && $0.type & 256 == 0 && $0.origin != "loc_book" }
        return await BookshelfRefresh.run(bookURLs: eligible.map(\.bookUrl)) { url in
            do {
                guard let current = try await repository.get(bookUrl: url) else { throw BookshelfEditError.missingBook }
                guard let sourceRow = try await BookSourceRepository(database: database).get(bookSourceUrl: current.origin) else { throw BookshelfDownloadsError.missingSource }
                var book = try DiscoveryStorage.book(current)
                let chapters = try await WebBook(source: DiscoveryStorage.source(sourceRow), client: client).chapterList(book: &book)
                let rows = try chapters.map { try DiscoveryStorage.row($0, defaults: BookChapterRow()) }
                try Task.checkCancellation()
                try await repository.saveChapterUpdate(bookURL: url, chapters: rows, checkedAt: book.lastCheckTime)
            } catch {
                if !(error is CancellationError) && !Task.isCancelled { try await repository.markUpdateFailed(bookURL: url) }
                throw error
            }
        }
    }
}
