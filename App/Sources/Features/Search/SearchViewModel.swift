import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class SearchViewModel {
    var query = ""
    var precisionSearch = false
    var scope = SearchScope()
    var filterWords = ""
    private(set) var availableSources: [BookSourceSummary] = []
    private(set) var shelfBooks: [BookRow] = []
    private(set) var readRecords: [ReadRecordRow] = []
    private(set) var hasSearched = false
    struct SourceFailure: Identifiable {
        let id: String
        let name: String
        let error: UserFacingError
    }
    private(set) var failures: [SourceFailure] = []
    var sourceFailures: [String] { failures.map { $0.error.displayText } }
    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    private(set) var completedSources = 0
    private(set) var totalSources = 0
    private(set) var failedSources = 0
    private(set) var userError: UserFacingError?
    var errorMessage: String? { userError?.displayText }
    func dismissError() { userError = nil }
    private(set) var history: [SearchKeyword] = []
    private let keywords: SearchKeywordRepository?
    private let bookshelf: BookshelfRepository?
    private let records: ReadProgressRepository?
    private let now: () -> Int64

    private let sources: BookSourceRepository
    private let client: any HttpClient
    private let concurrencyLimit: Int
    private let sourceTimeout: UInt64
    private let timeoutSleep: @Sendable (UInt64) async throws -> Void
    private var mergedResults = SearchModel()
    private var generation = 0
    private var searchTask: Task<Void, Never>?

    init(sources: BookSourceRepository, client: any HttpClient,
         keywords: SearchKeywordRepository? = nil, now: @escaping () -> Int64 = GsonDecoding.currentTimeMillis,
         bookshelf: BookshelfRepository? = nil, records: ReadProgressRepository? = nil,
         concurrencyLimit: Int = 8, sourceTimeout: TimeInterval = 30,
         timeoutSleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.sources = sources
        self.keywords = keywords
        self.bookshelf = bookshelf
        self.records = records
        self.now = now
        self.client = client
        self.concurrencyLimit = max(1, concurrencyLimit)
        self.sourceTimeout = UInt64(min(max(sourceTimeout.isFinite ? sourceTimeout : 30, 0.001), 3600) * 1_000_000_000)
        self.timeoutSleep = timeoutSleep
    }

    func cancel() {
        generation += 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    func loadHistory() async {
        do { history = try await keywords?.history() ?? [] }
        catch { userError = error.presentation(operation: "读取搜索历史", subject: nil) }
    }

    func clearHistory() async {
        do { try await keywords?.clear(); history = [] }
        catch { userError = error.presentation(operation: "清空搜索历史", subject: nil) }
    }

    var visibleResults: [SearchResult] { results.filter { SearchResultFilter.allows($0.book, words: filterWords) } }
    var matchingHistory: [SearchKeyword] { history.filter { query.isEmpty || $0.word.localizedCaseInsensitiveContains(query) } }
    var matchingShelf: [BookRow] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return shelfBooks.filter { key.isEmpty || $0.name.localizedCaseInsensitiveContains(key) || $0.author.localizedCaseInsensitiveContains(key) }
    }

    func loadInputHelp() async {
        await loadHistory()
        do {
            availableSources = try await sources.summaries()
            shelfBooks = try await bookshelf?.list() ?? []
            readRecords = try await records?.all() ?? []
        } catch { userError = error.presentation(operation: "读取搜索建议", subject: nil) }
    }

    func deleteHistory(_ keyword: SearchKeyword) async {
        do { _ = try await keywords?.delete(keyword); await loadHistory() }
        catch { userError = error.presentation(operation: "删除搜索历史", subject: keyword.word) }
    }

    func editQuery() {
        cancel()
        hasSearched = false
    }

    func isOnShelf(_ book: SearchBook) -> Bool {
        shelfBooks.contains {
            $0.bookUrl == book.bookUrl || ($0.name == book.name && ((book.author ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.author == book.author))
        }
    }

    func hasRead(_ book: SearchBook) -> Bool {
        readRecords.contains { record in
            guard record.bookName == book.name else { return false }
            let prefix = "\u{001e}authors:"
            let authors: [String]
            if record.author.hasPrefix(prefix) {
                let decoded = (try? JSONDecoder().decode([String].self, from: Data(record.author.dropFirst(prefix.count).utf8))) ?? []
                let nonblank = decoded.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                authors = nonblank.isEmpty ? [""] : nonblank
            } else { authors = [record.author] }
            return (book.author ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authors.contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0 == book.author
            }
        }
    }

    func search(_ text: String) async {
        cancel()
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        query = text
        results = []
        mergedResults = SearchModel()
        completedSources = 0
        totalSources = 0
        failedSources = 0
        failures = []
        hasSearched = !key.isEmpty
        userError = nil
        guard !key.isEmpty, !Task.isCancelled else { return }
        let request = generation
        let precise = precisionSearch
        isSearching = true
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.run(key: key, precise: precise, request: request)
        }
        searchTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if request == generation {
            isSearching = false
            searchTask = nil
        }
    }

    private func run(key: String, precise: Bool, request: Int) async {
        do {
            try await keywords?.record(key, at: now())
            await loadHistory()
            let all = try await sources.summaries()
            let resolved = scope.resolve(all)
            guard request == generation, !Task.isCancelled else { return }
            availableSources = all
            scope = resolved.scope
            let enabled = resolved.sources
            totalSources = enabled.count
            guard !enabled.isEmpty else {
                userError = UserFacingError(title: "无法搜索", message: all.isEmpty ? "请先导入书源。" : "当前范围没有启用的书源，请启用书源或调整搜索范围。", actions: [.manageSources])
                return
            }
            let client = client
            let sources = sources
            let timeout = sourceTimeout
            let sleep = timeoutSleep
            await withTaskGroup(of: (String, String, Result<[SearchBook], Error>).self) { group in
                var next = 0
                func enqueue() {
                    let row = enabled[next]
                    next += 1
                    group.addTask {
                        do {
                            guard let full = try await sources.get(bookSourceUrl: row.id) else { throw WebBookError.missingRule("bookSource") }
                            let source = try DiscoveryStorage.source(full)
                            return (row.name, row.id, .success(try await Self.searchSource(source, key: key, precise: precise,
                                                                        client: client, timeout: timeout, sleep: sleep)))
                        } catch { return (row.name, row.id, .failure(error)) }
                    }
                }
                for _ in 0..<min(concurrencyLimit, enabled.count) { enqueue() }
                for await (name, url, outcome) in group {
                    guard request == generation, !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    completedSources += 1
                    switch outcome {
                    case .success(let books):
                        results = mergedResults.merge(books, key: key, precision: precise)
                    case .failure(let error):
                        if let presentation = error.presentation(operation: "书源搜索", subject: name + " · " + url) {
                            failedSources += 1
                            if failures.count < 500 {
                                failures.append(SourceFailure(id: url, name: name, error: UserFacingError(title: presentation.title,
                                    message: String(presentation.message.prefix(2048)))))
                            }
                        }
                    }
                    if next < enabled.count { enqueue() }
                }
            }
        } catch {
            if request == generation, !Task.isCancelled { userError = error.presentation(operation: "搜索书籍", subject: key, actions: [.retry, .manageSources]) }
        }
    }

    private nonisolated static func searchSource(_ source: BookSource, key: String, precise: Bool,
                                                 client: any HttpClient, timeout: UInt64,
                                                 sleep: @escaping @Sendable (UInt64) async throws -> Void) async throws -> [SearchBook] {
        try await withThrowingTaskGroup(of: [SearchBook].self) { group in
            group.addTask {
                try await WebBook(source: source, client: client, precisionSearch: precise).search(key: key)
            }
            group.addTask {
                try await sleep(timeout)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next() ?? []
        }
    }
}
