import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class ExploreSourcesViewModel {
    private(set) var sources: [BookSource] = []
    private(set) var expandedURL: String?
    private(set) var kindsLoading = false
    var selectedGroup = ""
    var controlValues: [String: String] = [:]
    private(set) var controlNames: [String: String] = [:]
    private var kindGeneration = UUID()
    private var actionGeneration = UUID()
    private var valuesBySource: [String: [String: String]] = [:]
    var groups: [String] {
        Array(Set(sources.flatMap { ($0.bookSourceGroup ?? "").components(separatedBy: CharacterSet(charactersIn: ",，\n")) }
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
    }
    var filteredSources: [BookSource] {
        guard !selectedGroup.isEmpty else { return sources }
        return sources.filter { ($0.bookSourceGroup ?? "").components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.contains(selectedGroup) }
    }
    func collapse() {
        if let expandedURL { valuesBySource[expandedURL] = controlValues }
        kindGeneration = UUID(); expandedURL = nil; kinds = []; kindsLoading = false
    }

    func toggle(_ source: BookSource, client: any HttpClient, stateRepository: SourceStateRepository) async {
        if expandedURL == source.bookSourceUrl { collapse(); return }
        if let expandedURL { valuesBySource[expandedURL] = controlValues }
        expandedURL = source.bookSourceUrl
        controlValues = valuesBySource[source.bookSourceUrl ?? ""] ?? [:]; controlNames = [:]
        await loadKinds(source: source, client: client, stateRepository: stateRepository)
    }

    func refresh(_ source: BookSource, client: any HttpClient, stateRepository: SourceStateRepository) async {
        if expandedURL != source.bookSourceUrl {
            if let expandedURL { valuesBySource[expandedURL] = controlValues }
            expandedURL = source.bookSourceUrl
            controlValues = valuesBySource[source.bookSourceUrl ?? ""] ?? [:]; controlNames = [:]
        }
        await loadKinds(source: source, client: client, stateRepository: stateRepository, refresh: true)
    }

    func act(_ kind: ExploreKind, source: BookSource, client: any HttpClient, stateRepository: SourceStateRepository) async {
        let generation = kindGeneration, values = controlValues, action = UUID()
        actionGeneration = action
        let task = Task.detached {
            try await ExploreKinds.runControl(source: source, script: kind.action ?? "", values: values,
                                              client: client, stateRepository: stateRepository)
        }
        do {
            let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard kindGeneration == generation, actionGeneration == action, !Task.isCancelled else { return }
            controlValues = result.values
            if result.refresh { await loadKinds(source: source, client: client, stateRepository: stateRepository, refresh: true) }
        } catch {
            if kindGeneration == generation, actionGeneration == action, !(error is CancellationError) {
                userError = error.presentation(operation: "执行发现操作", subject: source.bookSourceName)
            }
        }
    }

    func moveToTop(_ source: BookSource, repository: BookSourceRepository) async {
        do {
            let url = source.bookSourceUrl
            try await repository.editSources { rows in
                var rows = rows
                if let index = rows.firstIndex(where: { $0.bookSourceUrl == url }) {
                    var selected = rows.remove(at: index)
                    selected.customOrder = 0
                    for i in rows.indices { rows[i].customOrder = i + 1 }
                    rows.insert(selected, at: 0)
                }
                return rows
            }
            await load(repository: repository)
        } catch { userError = error.presentation(operation: "置顶发现书源", subject: source.bookSourceName) }
    }

    func delete(_ source: BookSource, repository: BookSourceRepository) async {
        do {
            if let url = source.bookSourceUrl, let row = try await repository.get(bookSourceUrl: url) { _ = try await repository.delete(row) }
            if expandedURL == source.bookSourceUrl { collapse() }
            await load(repository: repository)
        } catch { userError = error.presentation(operation: "删除发现书源", subject: source.bookSourceName) }
    }
    private(set) var kinds: [ExploreKind] = []
    private(set) var isLoading = false
    private(set) var userError: UserFacingError?
    var errorMessage: String? { userError?.displayText }

    func load(repository: BookSourceRepository) async {
        isLoading = true; userError = nil
        defer { isLoading = false }
        do {
            let rows = try await repository.list(enabled: true)
            sources = try rows.filter { $0.enabledExplore && !($0.exploreUrl ?? "").isEmpty }
                .map { try JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode($0)) }
        } catch { userError = error.presentation(operation: "读取发现书源", subject: nil) }
    }

    func loadKinds(source: BookSource, client: any HttpClient, stateRepository: SourceStateRepository,
                   refresh: Bool = false) async {
        let generation = UUID(); kindGeneration = generation
        kindsLoading = true; userError = nil; kinds = []
        defer { if kindGeneration == generation { kindsLoading = false } }
        let values = controlValues
        let task = Task.detached {
            if refresh { try await ExploreKinds.clearCache(source: source, stateRepository: stateRepository) }
            return try await ExploreKinds.load(source: source, client: client, stateRepository: stateRepository, controlValues: values)
        }
        do {
            let loaded = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard kindGeneration == generation else { return }
            kinds = loaded
            let state = try await stateRepository.load(source: source.bookSourceUrl ?? "")
            guard kindGeneration == generation else { return }
            let stored = state["explore.infoMap"].flatMap { try? JSONDecoder().decode([String: String].self, from: Data($0.utf8)) } ?? [:]
            controlValues.merge(stored) { current, _ in current }
            for kind in loaded {
                if controlValues[kind.title] == nil { controlValues[kind.title] = kind.defaultValue ?? kind.chars.first ?? "" }
                if let script = kind.viewName {
                    let values = controlValues
                    let result = try await Task.detached {
                        try await ExploreKinds.runControl(source: source, script: script, values: values,
                            client: client, stateRepository: stateRepository)
                    }.value
                    guard kindGeneration == generation else { return }
                    controlNames[kind.title] = result.text
                }
            }
        } catch {
            if kindGeneration == generation, !(error is CancellationError) { userError = error.presentation(operation: "加载发现分类", subject: [source.bookSourceName, source.bookSourceUrl].compactMap { $0 }.joined(separator: " · ")) }
        }
    }
}

@Observable
@MainActor
final class ExploreViewModel {
    private(set) var books: [SearchBook] = []
    private(set) var isLoading = false
    private(set) var userError: UserFacingError?
    var errorMessage: String? { userError?.displayText }
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
        isLoading = false; userError = nil
        await loadNextPage()
    }

    func loadNextPage() async {
        guard !isLoading, hasMore, let url = category?.url else { return }
        let request = generation
        isLoading = true; userError = nil
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
            userError = error.presentation(operation: "加载发现书籍", subject: [category?.title, category?.url].compactMap { $0 }.joined(separator: " · "))
        }
    }
}
