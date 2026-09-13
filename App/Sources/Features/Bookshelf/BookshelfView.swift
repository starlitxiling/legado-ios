import SwiftUI
import LegadoCore

struct BookshelfView: View {
    @Environment(AppContainer.self) private var container
    @State private var model: BookshelfViewModel

    init(bookshelf: any BookshelfReading, groups: any BookGroupReading) {
        _model = State(initialValue: BookshelfViewModel(bookshelf: bookshelf, groups: groups))
    }

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isLoading && model.books.isEmpty {
                ProgressView("正在加载书架")
            } else if let error = model.errorMessage {
                VStack {
                    EmptyStateView(title: "加载失败", systemImage: "exclamationmark.triangle", message: error)
                    Button("重试") { Task { await refreshBooks() } }
                }
            } else if model.isEmpty {
                EmptyStateView(title: "书架为空", systemImage: "books.vertical",
                               message: model.selectedGroupID == -1 ? "加入书籍后即可在这里继续阅读" : "这个分组还没有书籍")
            } else if model.usesGrid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading, spacing: 20) {
                        ForEach(model.books, id: \.bookUrl) { book in
                            bookSummary(book)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                }
                .refreshable { await refreshBooks() }
            } else {
                List(model.books, id: \.bookUrl) { book in bookSummary(book) }
                    .refreshable { await refreshBooks() }
            }
        }
        .navigationTitle("书架")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("分组", selection: $model.selectedGroupID) {
                        Text("全部").tag(Int64(-1))
                        ForEach(model.groups, id: \.groupId) { group in
                            Text(group.groupName).tag(group.groupId)
                        }
                    }
                } label: { Label("分组", systemImage: "line.3.horizontal.decrease.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.usesGrid.toggle()
                } label: {
                    Label(model.usesGrid ? "切换列表" : "切换网格",
                          systemImage: model.usesGrid ? "list.bullet" : "square.grid.2x2")
                }
            }
        }
        .task(id: model.selectedGroupID) { await refreshBooks() }
        .onReceive(NotificationCenter.default.publisher(
            for: DatabaseLifecycleCoordinator.readyToRefreshNotification,
            object: container.databaseLifecycle
        )) { _ in
            Task { await refreshBooks() }
        }
    }

    private func refreshBooks() async {
        guard !container.databaseLifecycle.isSuspended else { return }
        await model.load()
    }

    private func bookSummary(_ book: BookRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.name.isEmpty ? "未命名书籍" : book.name).font(Theme.bookTitle)
            Text(book.author.isEmpty ? "未知作者" : book.author)
            Text("已读 \(min(max(0, book.durChapterIndex), max(0, book.totalChapterNum))) / 共 \(max(0, book.totalChapterNum)) 章")
            Text("来源：\(book.originName.isEmpty ? book.origin : book.originName)")
        }
        .font(Theme.detail)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }
}
