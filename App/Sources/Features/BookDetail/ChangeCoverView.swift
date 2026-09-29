import SwiftUI
import LegadoCore

struct ChangeCoverView: View {
    let book: Book
    let container: AppContainer
    let select: (String) async -> Void
    @State private var search: SearchViewModel
    @State private var ruleCover: String?
    @State private var selecting = false
    @Environment(\.themeColors) private var colors

    init(book: Book, container: AppContainer, select: @escaping (String) async -> Void) {
        self.book = book; self.container = container; self.select = select
        _search = State(initialValue: SearchViewModel(sources: container.bookSources, client: container.httpClient))
    }

    private var candidates: [CoverCandidate] {
        CoverCandidate.merge(name: book.name ?? "", author: book.author ?? "", rule: ruleCover,
                             results: search.results.flatMap(\.sources))
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 16) {
                ForEach(candidates) { item in
                    Button {
                        selecting = true
                        Task { await select(item.coverUrl); selecting = false }
                    } label: {
                        VStack(spacing: 6) {
                            RemoteImage(url: item.coverUrl, origin: item.origin, book: book)
                                .frame(width: 90, height: 128).clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(item.originName).font(.caption).lineLimit(1).foregroundStyle(colors.textSecondary)
                        }
                    }.buttonStyle(.plain).disabled(selecting).accessibilityIdentifier("cover." + item.originName)
                }
            }.padding(16)
            if search.failedSources > 0 {
                Text("\(search.failedSources) 个书源搜索失败").font(.caption).foregroundStyle(colors.textSecondary)
            }
        }
        .legadoNavigationTitle("换封面")
        .overlay(alignment: .top) { if search.isSearching || selecting { RefreshProgressBar() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(search.isSearching ? "停止" : "刷新") {
                    if search.isSearching { search.cancel() } else { Task { await start() } }
                }.accessibilityIdentifier("cover.searchToggle")
            }
        }
        .task { await start() }
        .onDisappear { search.cancel() }
    }

    private func start() async {
        if ruleCover == nil {
            do {
                let data = try await container.database.backupConfiguration(named: "coverRule.json")
                let rule = try data.map { try JSONDecoder().decode(CoverSearchRule.self, from: $0) } ?? .androidDefault
                if rule.enable { ruleCover = try await rule.search(book: book, client: container.httpClient) ?? "" }
            } catch {
                AppLogStore.shared.append("封面规则搜索出错: " + String(reflecting: error))
            }
        }
        search.precisionSearch = true
        await search.search(book.name ?? "")
    }
}
