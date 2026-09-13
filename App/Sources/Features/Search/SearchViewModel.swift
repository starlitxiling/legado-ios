import Foundation
import Observation
import LegadoCore

struct SearchResult: Identifiable {
    struct Identity: Hashable {
        let name: String
        let author: String
    }

    let id: Identity
    private(set) var sources: [SearchBook]
    var book: SearchBook { sources[0] }

    init(book: SearchBook) {
        id = Identity(name: (book.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                      author: (book.author ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        sources = [book]
    }

    mutating func merge(_ book: SearchBook) {
        guard !sources.contains(where: { $0.origin == book.origin }) else { return }
        sources.append(book)
        sources.sort { ($0.originOrder, $0.origin ?? "") < ($1.originOrder, $1.origin ?? "") }
    }
}

@Observable
@MainActor
final class SearchViewModel {
    var query = ""
    var precisionSearch = false
    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    private(set) var completedSources = 0
    private(set) var totalSources = 0
    private(set) var failedSources = 0
    private(set) var errorMessage: String?

    private let sources: BookSourceRepository
    private let client: any HttpClient
    private let concurrencyLimit: Int
    private let sourceTimeout: UInt64
    private let timeoutSleep: @Sendable (UInt64) async throws -> Void
    private var generation = 0
    private var searchTask: Task<Void, Never>?

    init(sources: BookSourceRepository, client: any HttpClient,
         concurrencyLimit: Int = 8, sourceTimeout: TimeInterval = 30,
         timeoutSleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.sources = sources
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

    func search(_ text: String) async {
        cancel()
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        query = text
        results = []
        completedSources = 0
        totalSources = 0
        failedSources = 0
        errorMessage = nil
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
            let enabled = try await sources.list(enabled: true)
            guard request == generation, !Task.isCancelled else { return }
            totalSources = enabled.count
            let client = client
            let timeout = sourceTimeout
            let sleep = timeoutSleep
            await withTaskGroup(of: Result<[SearchBook], Error>.self) { group in
                var next = 0
                func enqueue() {
                    let row = enabled[next]
                    next += 1
                    group.addTask {
                        do {
                            let source = try DiscoveryStorage.source(row)
                            return .success(try await Self.searchSource(source, key: key, precise: precise,
                                                                        client: client, timeout: timeout, sleep: sleep))
                        } catch { return .failure(error) }
                    }
                }
                for _ in 0..<min(concurrencyLimit, enabled.count) { enqueue() }
                for await outcome in group {
                    guard request == generation, !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    completedSources += 1
                    switch outcome {
                    case .success(let books):
                        for book in books {
                            let result = SearchResult(book: book)
                            if let index = results.firstIndex(where: { $0.id == result.id }) {
                                results[index].merge(book)
                            } else { results.append(result) }
                        }
                    case .failure: failedSources += 1
                    }
                    if next < enabled.count { enqueue() }
                }
            }
        } catch {
            if request == generation, !Task.isCancelled { errorMessage = error.localizedDescription }
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
