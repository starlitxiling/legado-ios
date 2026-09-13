import SwiftUI
import LegadoCore

struct ExploreBookListView: View {
    let kind: ExploreKind
    let container: AppContainer
    @State private var model: ExploreViewModel

    init(source: BookSource, kind: ExploreKind, container: AppContainer) {
        self.kind = kind; self.container = container
        _model = State(initialValue: ExploreViewModel(source: source, client: container.httpClient))
    }

    var body: some View {
        List {
            ForEach(model.books, id: \.bookUrl) { book in
                NavigationLink {
                    BookDetailView(results: [book], container: container)
                } label: {
                    HStack {
                        RemoteImage(url: book.coverUrl, origin: book.origin).frame(width: 48, height: 68)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(book.name ?? "未命名书籍").font(Theme.bookTitle)
                            Text(book.author ?? "未知作者").font(Theme.detail)
                            Text(book.latestChapterTitle ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if model.isLoading { ProgressView("正在加载书单") }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            if model.hasMore && !model.isLoading {
                Button(model.errorMessage == nil ? "加载更多" : "重试") { Task { await model.loadNextPage() } }
            }
            if !model.hasMore { Text(model.books.isEmpty ? "暂无书籍" : "已加载全部书籍").foregroundStyle(.secondary) }
        }
        .navigationTitle(kind.title)
        .task { await model.select(kind) }
        .refreshable { await model.select(kind) }
    }
}
