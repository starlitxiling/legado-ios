import Foundation
import Observation
import LegadoCore

@Observable @MainActor
final class RssSourceListModel {
    var sources: [RssSource] = []
    var selectedGroup = "全部"
    var error: String?
    var importing = false
    let repository: RssRepository
    let client: any HttpClient
    var groups: [String] { ["全部"] + Set(sources.flatMap(\.groups)).sorted() }
    var visibleSources: [RssSource] { sources.filter { selectedGroup == "全部" || $0.groups.contains(selectedGroup) } }
    init(repository: RssRepository, client: any HttpClient) { self.repository = repository; self.client = client }
    func reload() async {
        do { sources = try await repository.sources() } catch { self.error = String(describing: error) }
    }
    func save(_ source: RssSource, replacing oldURL: String? = nil) async throws {
        guard !source.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RssError.invalidSource }
        if let oldURL { try await repository.renameSource(source, replacing: oldURL) }
        else { try await repository.saveSources([source]) }
        await reload()
    }
    func delete(_ source: RssSource) async {
        do { try await repository.deleteSource(source.sourceUrl); await reload() }
        catch { self.error = String(describing: error) }
    }
    func importText(_ text: String) async {
        guard !importing else { return }
        importing = true; error = nil
        defer { importing = false }
        do {
            var queue = [text]
            var visited = Set<String>()
            var values: [RssSource] = []
            while !queue.isEmpty {
                try Task.checkCancellation()
                let text = queue.removeFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                var result = SourceImporter().parseRssSources(text)
                if let url = URL(string: text), ["https", "http"].contains(url.scheme ?? ""), url.host != nil { result = .urls([text]) }
                switch result {
                case let .sources(sources): values += sources
                case let .urls(urls):
                    for value in urls where visited.insert(value).inserted {
                        guard visited.count <= 50, let url = URL(string: value), ["https", "http"].contains(url.scheme ?? "") else { throw RssError.invalidURL }
                        let response = try await client.send(HttpRequest(url: url))
                        guard (200..<300).contains(response.status) else { throw RssError.httpStatus(response.status) }
                        queue.append(try ResponseDecoder.decode(response.body, headers: response.headers))
                    }
                case .invalid: throw RssError.invalidSource
                }
            }
            try await repository.saveSources(values)
            await reload()
        } catch { self.error = String(describing: error) }
    }
}

@Observable @MainActor
final class RssArticlesModel {
    let source: RssSource
    let repository: RssRepository
    let service: RssService
    var articles: [RssArticle] = []
    var columnIndex = 0
    var loading = false
    var error: String?
    var nextURL: String?
    private var page = 1
    private var generation = 0
    private var visited = Set<String>()
    var columns: [RssColumn] = []
    var column: RssColumn { columns[min(columnIndex, columns.count - 1)] }
    init(source: RssSource, repository: RssRepository, client: any HttpClient) {
        self.source = source; self.repository = repository; service = repository.service(client: client)
    }
    func refresh() async {
        generation += 1
        let token = generation
        do { columns = try service.columns(source: source) }
        catch { self.error = String(describing: error); return }
        loading = false; articles = []; page = 1; visited = []; nextURL = column.url
        do {
            let cached = try await repository.articles(origin: source.sourceUrl, sort: column.name)
            guard token == generation else { return }
            articles = cached
        } catch { self.error = String(describing: error) }
        guard token == generation else { return }
        await loadMore(reset: true)
    }
    func loadMore(reset: Bool = false) async {
        guard !loading, let url = nextURL else { return }
        let reset = reset || page == 1
        let token = generation
        let selected = column
        loading = true; error = nil
        defer { if token == generation { loading = false } }
        do {
            let result = try await service.articles(source: source, sort: selected.name, url: url, page: page, existing: reset ? [] : articles)
            guard token == generation else { return }
            var rows = result.articles
            let offset = reset ? 0 : articles.count
            for index in rows.indices { rows[index].order = Int64(offset + index) }
            let replacing = reset && source.ruleNextPage?.isEmpty == false ? selected : nil
            try await repository.saveArticles(rows, replacingColumn: replacing, origin: source.sourceUrl)
            let stored = try await repository.articles(origin: source.sourceUrl, sort: selected.name)
            guard token == generation else { return }
            let read = Dictionary(stored.map { ($0.identity, $0.read) }, uniquingKeysWith: { _, latest in latest })
            for index in rows.indices { rows[index].read = read[rows[index].identity] ?? false }
            articles = reset ? rows : articles + rows
            visited.insert(url)
            nextURL = result.nextPageURL
            if source.ruleNextPage?.uppercased() != "PAGE", let nextURL, visited.contains(nextURL) { self.nextURL = nil }
            page += 1
        } catch { if token == generation { self.error = String(describing: error) } }
    }
}

@Observable @MainActor
final class RssReadModel {
    var article: RssArticle
    let source: RssSource
    let repository: RssRepository
    let service: RssService
    var content: RssReadContent?
    var starred = false
    var error: String?
    private let startHTML: String?
    var isStartPage: Bool { startHTML != nil }
    private let now: () -> Int64
    init(article: RssArticle, source: RssSource, repository: RssRepository, client: any HttpClient,
         startHTML: String? = nil, now: @escaping () -> Int64 = GsonDecoding.currentTimeMillis) {
        self.article = article; self.source = source; self.repository = repository; service = repository.service(client: client)
        self.now = now; self.startHTML = startHTML
    }
    func load() async {
        do {
            if let startHTML {
                content = .html(startHTML, baseURL: source.sourceUrl)
                return
            }
            content = try await service.content(article: article, source: source)
            if case let .html(html, _) = content { article.content = html }
            try await repository.saveArticles([article])
            try await repository.markRead(article, time: now())
            starred = try await repository.stars().contains { $0.origin == article.origin && $0.link == article.link }
        } catch { self.error = String(describing: error) }
    }
    func toggleStar() async {
        guard !isStartPage else { return }
        do {
            try await repository.setStar(article, starred: !starred, time: now())
            starred.toggle()
        } catch { self.error = String(describing: error) }
    }
}

// 起始页不创建文章、已读记录或收藏。
enum RssSourceDestination: Equatable {
    case singleURL, startHTML(String), articles
    init(source: RssSource) {
        if source.singleUrl { self = .singleURL }
        else if let html = source.startHtml, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self = .startHTML(html) }
        else { self = .articles }
    }
}
