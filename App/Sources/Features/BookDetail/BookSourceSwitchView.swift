import SwiftUI
import LegadoCore

struct BookSourceSwitchView: View {
    let book: Book?
    let initial: [SearchBook]
    let container: AppContainer
    let select: (SearchBook) async -> Void
    @State private var search: SearchViewModel
    @State private var checking = Set<String>()
    @State private var states: [String: String] = [:]
    @State private var checkTasks: [String: Task<Void, Never>] = [:]
    @State private var checkIDs: [String: UUID] = [:]
    @State private var selecting = false
    @Environment(\.themeColors) private var colors

    init(book: Book?, initial: [SearchBook], container: AppContainer, select: @escaping (SearchBook) async -> Void) {
        self.book = book; self.initial = initial; self.container = container; self.select = select
        _search = State(initialValue: SearchViewModel(sources: container.bookSources, client: container.httpClient))
    }

    private var results: [SearchBook] {
        var seen = Set<String>()
        return (initial + search.results.flatMap(\.sources)).filter {
            guard let url = $0.bookUrl, seen.insert(url).inserted else { return false }
            return book == nil || ($0.name == book?.name && ($0.author ?? "") == (book?.author ?? ""))
        }
    }

    var body: some View {
        List {
            ForEach(results, id: \.bookUrl) { result in
                HStack {
                    Button {
                        selecting = true
                        Task { await select(result); selecting = false }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.originName ?? result.origin ?? "未知来源").font(.system(size: 16))
                            Text(result.latestChapterTitle ?? "暂无最新章节").font(.system(size: 13)).foregroundStyle(colors.textSecondary)
                            Text(result.respondTime < 0 ? "响应时间未知" : "\(result.respondTime) ms")
                                .font(.system(size: 12)).foregroundStyle(colors.textSecondary)
                            if let state = states[result.origin ?? ""] { Text(state).font(.caption).foregroundStyle(colors.textSecondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).disabled(selecting)
                    Button("校验") { check(result) }.font(.system(size: 13))
                        .disabled(checking.contains(result.origin ?? ""))
                }.padding(.vertical, 4)
            }
            if results.isEmpty && !search.isSearching { EmptyText(text: "未找到可用书源") }
            if let error = search.errorMessage { Text(error).foregroundStyle(colors.error) }
            if search.failedSources > 0 { Text("\(search.failedSources) 个书源搜索失败").font(.caption) }
        }.listStyle(.plain).legadoNavigationTitle("换源")
            .overlay(alignment: .top) { if search.isSearching || selecting || !checking.isEmpty { RefreshProgressBar() } }
            .toolbar {
                Button(search.isSearching || !checking.isEmpty ? "停止" : "搜索") {
                    if search.isSearching || !checking.isEmpty { stop() }
                    else { Task { await search.search(book?.name ?? "") } }
                }
            }
            .task { search.precisionSearch = true; await search.search(book?.name ?? "") }
            .onDisappear { stop() }
    }

    private func stop() {
        search.cancel()
        for task in checkTasks.values { task.cancel() }
        checkTasks = [:]; checkIDs = [:]; checking = []
    }

    private func check(_ result: SearchBook) {
        guard let origin = result.origin, !checking.contains(origin) else { return }
        checking.insert(origin)
        let id = UUID(); checkIDs[origin] = id
        checkTasks[origin] = Task {
            defer { if checkIDs[origin] == id { checking.remove(origin); checkTasks[origin] = nil; checkIDs[origin] = nil } }
            do {
                guard let row = try await container.bookSources.get(bookSourceUrl: origin) else { throw BookshelfEditError.missingBook }
                let source = try DiscoveryStorage.source(row)
                let state = try await container.sourceChecker.check(source: source, keyword: book?.name ?? "我的", timeout: 30)
                guard checkIDs[origin] == id, !Task.isCancelled else { return }
                states[origin] = state.succeeded ? "校验通过 · \(state.elapsedMilliseconds) ms" : state.steps.compactMap(\.error).joined(separator: "\n")
            } catch { if !Task.isCancelled { states[origin] = error.localizedDescription } }
        }
    }
}
