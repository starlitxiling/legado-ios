import SwiftUI
import LegadoCore

struct SearchView: View {
    @State private var model: SearchViewModel
    private let container: AppContainer
    private let onRead: ((Book, Int) -> Void)?

    init(container: AppContainer, onRead: ((Book, Int) -> Void)? = nil) {
        self.container = container
        self.onRead = onRead
        _model = State(initialValue: SearchViewModel(sources: container.bookSources, client: container.httpClient,
                                                    keywords: SearchKeywordRepository(database: container.database)))
    }

    var body: some View {
        @Bindable var model = model
        List {
            if !model.history.isEmpty {
                Section("搜索历史") {
                    ForEach(model.history, id: \.word) { keyword in
                        Button(keyword.word) { Task { await model.search(keyword.word) } }
                    }
                    Button("清空历史", role: .destructive) { Task { await model.clearHistory() } }
                }
            }
            Section {
                Toggle("精准搜索", isOn: $model.precisionSearch)
                if model.isSearching {
                    ProgressView(value: Double(model.completedSources), total: Double(max(1, model.totalSources)))
                    HStack {
                        Text("已搜索 \(model.completedSources) / \(model.totalSources) 个书源")
                        Spacer()
                        Button("取消") { model.cancel() }
                    }
                }
                if model.failedSources > 0 {
                    Text("\(model.failedSources) 个书源搜索失败或超时").foregroundStyle(.secondary)
                }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }
            Section {
                ForEach(model.results) { result in
                    NavigationLink {
                        BookDetailView(results: result.sources, container: container, onRead: onRead)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            RemoteImage(url: result.book.coverUrl, origin: result.book.origin)
                                .frame(width: 48, height: 68)
                            Text(result.book.name ?? "未命名书籍").font(Theme.bookTitle)
                            Text(result.book.author ?? "未知作者")
                            Text("\(result.sources.count) 个来源")
                            if let chapter = result.book.latestChapterTitle, !chapter.isEmpty {
                                Text("最新章节：\(chapter)")
                            }
                        }
                        .font(Theme.detail)
                    }
                }
                if model.results.isEmpty && !model.isSearching {
                    Text(model.query.isEmpty ? "输入书名或作者开始搜索" : "暂无搜索结果")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("搜索")
        .task { await model.loadHistory() }
        .searchable(text: $model.query, prompt: "书名或作者")
        .onSubmit(of: .search) { Task { await model.search(model.query) } }
        .onDisappear { model.cancel() }
    }
}
