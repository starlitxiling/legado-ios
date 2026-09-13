import SwiftUI
import LegadoCore

struct ExploreView: View {
    let container: AppContainer
    @State private var model = ExploreSourcesViewModel()

    var body: some View {
        ScrollViewReader { proxy in
        List {
            if model.isLoading { ProgressView("正在加载书源") }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            ForEach(model.sources, id: \.bookSourceUrl) { source in
                NavigationLink(source.bookSourceName ?? "未命名书源") {
                    ExploreCategoriesView(source: source, container: container)
                }
                .id(source.bookSourceUrl)
            }
            if !model.isLoading && model.sources.isEmpty {
                Text("暂无启用发现的书源，请先导入书源").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("发现")
        .task { await model.load(repository: container.bookSources) }
        .refreshable { await model.load(repository: container.bookSources) }
        .overlay(alignment: .trailing) {
            if AppPreferences.shared.boolean("showDiscoveryFastScroller") {
                Menu {
                    ForEach(model.sources, id: \.bookSourceUrl) { source in
                        Button(source.bookSourceName ?? "未命名书源") { proxy.scrollTo(source.bookSourceUrl, anchor: .top) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down").padding() }
            }
        }
        }
    }
}

private struct ExploreCategoriesView: View {
    let source: BookSource
    let container: AppContainer
    @State private var model = ExploreSourcesViewModel()

    var body: some View {
        List {
            if model.isLoading { ProgressView("正在加载分类") }
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
                Button("重试") { Task { await reloadKinds() } }
            }
            ForEach(model.kinds.indices, id: \.self) { index in
                let kind = model.kinds[index]
                if kind.type == "url" && !kind.isHeading {
                    NavigationLink(kind.title) {
                        ExploreBookListView(source: source, kind: kind, container: container)
                    }
                } else {
                    Text(kind.title).font(.headline).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(source.bookSourceName ?? "发现分类")
        .task { await model.loadKinds(source: source, client: container.httpClient,
                                     stateRepository: SourceStateRepository(database: container.database)) }
        .refreshable { await reloadKinds() }
    }

    private func reloadKinds() async {
        let repository = SourceStateRepository(database: container.database)
        await model.loadKinds(source: source, client: container.httpClient, stateRepository: repository, refresh: true)
    }
}
