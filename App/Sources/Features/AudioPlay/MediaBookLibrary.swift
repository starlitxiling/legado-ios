import Foundation
import Observation
import LegadoCore

@Observable @MainActor
final class MediaBookLibrary {
    private(set) var book: Book
    private(set) var chapters: [BookChapter] = []
    private(set) var source: BookSource?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private let database: AppDatabase
    private let client: any HttpClient
    private let cookies = CookieStore()
    private var imageDownloader: ImageDownloader?
    private var saveTask: Task<Void, Error>?
    private let imageRetention: () -> (previous: Int, preDownload: Int)

    init(book: Book, database: AppDatabase, client: any HttpClient,
         imageRetention: @escaping () -> (previous: Int, preDownload: Int) = { (0, 0) }) {
        self.book = book; self.database = database; self.client = client
        self.imageRetention = imageRetention
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            guard let row = try await BookSourceRepository(database: database).get(bookSourceUrl: book.origin ?? "") else {
                throw WebBookError.missingRule("书源不存在")
            }
            let source = try DiscoveryStorage.source(row)
            let repository = BookshelfRepository(database: database)
            if let saved = try await repository.get(bookUrl: book.bookUrl ?? "") {
                book = try DiscoveryStorage.book(saved)
            } else {
                var hidden = try DiscoveryStorage.row(book, defaults: BookRow())
                hidden.type |= 1024
                try await repository.upsert(hidden)
            }
            for cookie in try await CookieRepository(database: database).list() {
                await cookies.setCookie(url: cookie.url, cookie: cookie.cookie)
            }
            var updated = book
            let chapters = try await WebBook(source: source, client: client).chapterList(book: &updated)
            try Task.checkCancellation()
            self.book = updated; self.source = source
            self.chapters = chapters.filter { !$0.isVolume }
            guard !self.chapters.isEmpty else { throw WebBookError.emptyToc }
            let imageClient = (client as? any SourceSessionClientProviding)?.client(for: source) ?? client
            imageDownloader = ImageDownloader(client: imageClient, cookies: cookies)
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    var initialChapter: Int { chapters.firstIndex { $0.index == book.durChapterIndex } ?? 0 }

    func audio(_ index: Int) async throws -> MediaResource {
        guard let source, chapters.indices.contains(index) else { throw WebBookError.emptyToc }
        let chapter = chapters[index]
        let raw = try await WebBook(source: source, client: client, cookies: cookies).content(book: book, chapter: chapter, includeTitle: false).rawContent
        for cookie in try await CookieRepository(database: database).list() {
            await cookies.setCookie(url: cookie.url, cookie: cookie.cookie)
        }
        return try await MediaContentResolver.audioAddress(raw, source: source, book: book, chapter: chapter, client: client, cookies: cookies)
    }

    func images(_ index: Int) async throws -> [MediaResource] {
        guard let source, chapters.indices.contains(index) else { throw WebBookError.emptyToc }
        let chapter = chapters[index]
        let next = chapters.indices.contains(index + 1) ? chapters[index + 1].url : nil
        let result = try await WebBook(source: source, client: client).content(book: book, chapter: chapter,
            nextChapterUrl: next, includeTitle: false)
        let base = URL(string: UrlOptions.parse(chapter.url ?? "").url,
                       relativeTo: URL(string: chapter.baseUrl ?? book.tocUrl ?? source.bookSourceUrl ?? ""))?.absoluteString ?? ""
        let resources = try MediaContentResolver.images(result.rawContent, baseURL: base)
        try await imageDownloader?.recordChapterImages(book: book, chapterIndex: chapter.index, urls: resources.map(\.imageRule))
        return resources
    }

    func image(_ resource: MediaResource) async throws -> Data {
        guard let imageDownloader else { throw WebBookError.missingRule("图片加载器未初始化") }
        return try await imageDownloader.load(url: resource.imageRule, source: source, book: book, isCover: false,
                                              validate: { MangaReaderModel.canDecodeImage($0) })
    }

    func save(chapter index: Int, position: Int) async throws {
        try await enqueueSave(chapter: index, position: position)?.value
    }

    private func enqueueSave(chapter index: Int, position: Int) -> Task<Void, Error>? {
        guard chapters.indices.contains(index) else { return nil }
        let chapter = chapters[index]
        let repository = BookshelfRepository(database: database)
        let url = book.bookUrl ?? ""
        let previous = saveTask
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let task = Task { [self] in
            _ = try? await previous?.value
            _ = try await repository.updateProgress(bookUrl: url, chapterIndex: chapter.index, chapterPos: position,
                chapterTitle: chapter.title, readTime: timestamp)
            book.durChapterIndex = chapter.index; book.durChapterPos = position
            let retention = imageRetention()
            try await imageDownloader?.pruneChapterImages(book: book, chapterIndex: chapter.index,
                retainPrevious: retention.previous, preDownload: retention.preDownload)
        }
        saveTask = task
        return task
    }

    func record(chapter: Int, position: Int) {
        let pending = enqueueSave(chapter: chapter, position: position)
        Task {
            do { try await pending?.value }
            catch { errorMessage = "保存进度失败：" + error.localizedDescription }
        }
    }
}
