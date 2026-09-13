import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class ExploreSourcesViewModel {
    private(set) var sources: [BookSource] = []
    private(set) var kinds: [ExploreKind] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load(repository: BookSourceRepository) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let rows = try await repository.list(enabled: true)
            sources = try rows.filter { $0.enabledExplore && !($0.exploreUrl ?? "").isEmpty }
                .map { try JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode($0)) }
        } catch { errorMessage = error.localizedDescription }
    }

    func loadKinds(source: BookSource, client: any HttpClient, stateRepository: SourceStateRepository,
                   refresh: Bool = false) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        let task = Task.detached {
            if refresh { try await ExploreKinds.clearCache(source: source, stateRepository: stateRepository) }
            return try await ExploreKinds.load(source: source, client: client, stateRepository: stateRepository)
        }
        do {
            kinds = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        } catch {
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }
}

@Observable
@MainActor
final class ExploreViewModel {
    private(set) var books: [SearchBook] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasMore = true
    private var category: ExploreKind?
    private var page = 1
    private var generation = 0
    private let fetch: (String, Int) async throws -> [SearchBook]

    init(fetch: @escaping (String, Int) async throws -> [SearchBook]) { self.fetch = fetch }

    convenience init(source: BookSource, client: any HttpClient) {
        let web = WebBook(source: source, client: client)
        self.init { url, page in try await web.explore(url: url, page: page) }
    }

    func select(_ category: ExploreKind) async {
        generation += 1
        self.category = category; page = 1; books = []; hasMore = !category.isHeading
        isLoading = false; errorMessage = nil
        await loadNextPage()
    }

    func loadNextPage() async {
        guard !isLoading, hasMore, let url = category?.url else { return }
        let request = generation
        isLoading = true; errorMessage = nil
        defer { if request == generation { isLoading = false } }
        do {
            let results = try await fetch(url, page)
            try Task.checkCancellation()
            guard request == generation else { return }
            var seen = Set(books.compactMap(\.bookUrl))
            let additions = results.filter { book in
                guard let url = book.bookUrl, !url.isEmpty else { return false }
                return seen.insert(url).inserted
            }
            books += additions
            hasMore = !results.isEmpty && page < Int(Int32.max)
            if hasMore { page += 1 }
        } catch {
            guard request == generation, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
