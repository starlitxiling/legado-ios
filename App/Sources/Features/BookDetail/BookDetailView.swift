import SwiftUI
import LegadoCore

struct BookDetailView: View {
    @State private var model: BookDetailViewModel
    @State private var confirmingAdd = false
    private let container: AppContainer
    private let onRead: ((Book, Int) -> Void)?

    init(results: [SearchBook], container: AppContainer, onRead: ((Book, Int) -> Void)? = nil) {
        self.container = container
        self.onRead = onRead
        _model = State(initialValue: BookDetailViewModel(results: results, sources: container.bookSources,
            bookshelf: container.bookshelf, client: container.httpClient))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    RemoteImage(url: model.book?.coverUrl ?? model.results.first?.coverUrl,
                                origin: model.book?.origin ?? model.results.first?.origin, book: model.book)
                        .frame(width: 90, height: 125)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.book?.name ?? model.results.first?.name ?? "书籍详情").font(.title2)
                        Text(model.book?.author ?? "")
                        Text(model.book?.latestChapterTitle ?? "").font(.caption)
                    }
                }
                if model.isLoading { ProgressView("正在加载详情") }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                    Button("重试") { Task { await model.load() } }
                }
                Picker("来源", selection: Binding(get: { model.selectedSourceIndex }, set: { index in
                    Task { await model.selectSource(index) }
                })) {
                    ForEach(model.results.indices, id: \.self) { index in
                        Text(model.results[index].originName ?? model.results[index].origin ?? "未知来源").tag(index)
                    }
                }
                .disabled(model.isSaving)
                Text(model.book?.intro ?? "暂无简介")
                Button(model.isOnBookshelf ? "移出书架" : "加入书架") {
                    if !model.isOnBookshelf, AppPreferences.shared.boolean("showAddToShelfAlert") { confirmingAdd = true }
                    else { Task { await model.toggleBookshelf() } }
                }
                .confirmationDialog("将这本书加入书架？", isPresented: $confirmingAdd, titleVisibility: .visible) {
                    Button("加入书架") { Task { await model.toggleBookshelf() } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.book == nil || model.isLoading || model.isSaving)
                if let book = model.book, let source = model.source {
                    if book.mediaKind != .text {
                        NavigationLink("打开") { MediaReaderDestination(book: book, container: container) }
                    } else {
                    NavigationLink("查看目录") {
                        TocView(book: book, source: source, container: container) { index in
                            onRead?(book, index)
                        }
                    }
                    Button("开始阅读") { onRead?(book, book.durChapterIndex) }
                        .disabled(onRead == nil)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("书籍详情")
        .task {
            if model.book == nil { await model.load() }
            else { await model.refreshShelfState() }
        }
    }
}
