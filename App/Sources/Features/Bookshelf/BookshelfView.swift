import SwiftUI
import LegadoCore

struct BookshelfView: View {
    private struct BookSheet: Identifiable {
        let id = UUID()
        let book: BookRow
        let editing: Bool
    }
    @Environment(AppContainer.self) private var container
    @State private var model: BookshelfViewModel
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var actionError: String?
    @State private var confirmingDelete = false
    @AppStorage("bookshelfSort") private var sortValue = 0
    @State private var bookSheet: BookSheet?

    init(bookshelf: any BookshelfReading, groups: any BookGroupReading) {
        _model = State(initialValue: BookshelfViewModel(bookshelf: bookshelf, groups: groups))
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if selecting { selectionActions }
            if let actionError { Text(actionError).foregroundStyle(.red).font(.caption) }
            if let report = container.downloads.refreshReport, !report.failures.isEmpty {
                Text("已更新 \(report.updated.count) 本，\(report.failures.count) 本失败，可在错误分组重试。")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                .refreshable { await updateChapters() }
            } else {
                List(model.books, id: \.bookUrl) { book in bookSummary(book) }
                    .refreshable { await updateChapters() }
            }
            }
        }
        .navigationTitle("书架")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    LocalImportView(database: container.database)
                } label: { Label("导入本地书", systemImage: "square.and.arrow.down") }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    NavigationLink("编辑分组") { GroupEditView(repository: container.bookGroups) }
                    Picker("分组", selection: $model.selectedGroupID) {
                        Text("全部").tag(Int64(-1))
                        ForEach(model.groups, id: \.groupId) { group in
                            Text(group.groupName).tag(group.groupId)
                        }
                    }
                    Picker("默认排序", selection: $sortValue) {
                        Text("最近阅读").tag(0)
                        Text("最近更新").tag(1)
                        Text("书名").tag(2)
                        Text("手动顺序").tag(3)
                        Text("综合排序").tag(4)
                        Text("作者").tag(5)
                    }
                    Button("更新章节") { Task { await updateChapters() } }
                        .disabled(container.downloads.isRefreshing)
                    Button(selecting ? "结束多选" : "多选书籍") { selecting.toggle(); selected.removeAll() }
                    NavigationLink("下载中心") { DownloadCenterView(model: container.downloads) }
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
        .onChange(of: sortValue) { _, _ in Task { await refreshBooks() } }
        .sheet(item: $bookSheet, onDismiss: { Task { await refreshBooks() } }) { item in
            NavigationStack {
                Group {
                    if item.editing { BookInfoEditView(book: item.book, repository: container.bookshelf) }
                    else { BookCacheExportView(book: item.book, model: container.downloads) }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { bookSheet = nil } } }
            }
        }
        .confirmationDialog("删除所选书籍？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除 \(selected.count) 本书", role: .destructive) {
                Task { await perform { try await container.bookshelf.deleteBooks(Array(selected)); selected.removeAll() } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: DatabaseLifecycleCoordinator.readyToRefreshNotification,
            object: container.databaseLifecycle
        )) { _ in
            Task { await refreshBooks() }
        }
    }

    private func refreshBooks() async {
        guard !container.databaseLifecycle.isSuspended else { return }
        do { try await container.bookGroups.ensureBuiltinGroups() }
        catch { actionError = error.localizedDescription; return }
        model.sort = BookshelfSort(rawValue: sortValue) ?? .lastRead
        await model.load()
        selected.formIntersection(Set(model.books.map(\.bookUrl)))
    }

    private func updateChapters() async {
        guard !container.databaseLifecycle.isSuspended else { return }
        await container.downloads.refresh()
        await refreshBooks()
    }

    private var selectionActions: some View {
        HStack {
            Button("全选") { selected = Set(model.books.map(\.bookUrl)) }
            Text("\(selected.count) 本")
            Menu("移组") {
                Button("移至未分组") { Task { await moveSelection(to: 0) } }
                ForEach(model.groups.filter { $0.groupId > 0 }, id: \.groupId) { group in
                    Button(group.groupName) {
                        Task { await moveSelection(to: group.groupId) }
                    }
                }
            }.disabled(selected.isEmpty)
            Button("更新") { Task { await container.downloads.refresh(model.books.filter { selected.contains($0.bookUrl) }); await refreshBooks() } }
                .disabled(selected.isEmpty || container.downloads.isRefreshing)
            Button("缓存") { Task { await container.downloads.download(model.books.filter { selected.contains($0.bookUrl) }) } }
                .disabled(selected.isEmpty)
            Button("删除", role: .destructive) { confirmingDelete = true }.disabled(selected.isEmpty)
        }.font(.caption).padding(8)
    }

    @MainActor
    private func moveSelection(to group: Int64) async {
        await perform {
            let groups = try await container.bookGroups.list()
            let mask = groups.filter { $0.groupId > 0 }.reduce(Int64(0)) { $0 | $1.groupId }
            try await container.bookshelf.move(bookURLs: Array(selected), from: mask, to: group)
            selected.removeAll()
        }
    }

    @MainActor
    private func perform(_ action: () async throws -> Void) async {
        do { try await action(); actionError = nil; await refreshBooks() }
        catch { actionError = error.localizedDescription }
    }

    private func bookSummary(_ book: BookRow) -> some View {
        HStack {
            if selecting {
                Button {
                    if !selected.insert(book.bookUrl).inserted { selected.remove(book.bookUrl) }
                } label: { Image(systemName: selected.contains(book.bookUrl) ? "checkmark.circle.fill" : "circle") }
                .buttonStyle(.borderless)
            }
            NavigationLink {
            ReaderView(book: book, database: container.database, client: container.httpClient)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RemoteImage(url: book.customCoverUrl ?? book.coverUrl, origin: book.origin,
                            book: try? DiscoveryStorage.book(book))
                    .frame(width: 60, height: 84)
                Text(book.name.isEmpty ? "未命名书籍" : book.name).font(Theme.bookTitle)
                Text(book.author.isEmpty ? "未知作者" : book.author)
                if book.lastCheckCount > 0 { Text("新增 \(book.lastCheckCount) 章").foregroundStyle(Theme.accent) }
                if book.type & 16 != 0 { Text("更新失败").foregroundStyle(.red) }
                Text("已读 \(min(max(0, book.durChapterIndex), max(0, book.totalChapterNum))) / 共 \(max(0, book.totalChapterNum)) 章")
                Text("来源：\(book.originName.isEmpty ? book.origin : book.originName)")
            }
            .font(Theme.detail)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        }
            .disabled(selecting)
            .contextMenu {
                Button("编辑书籍信息") { bookSheet = BookSheet(book: book, editing: true) }
                Button("缓存与导出") { bookSheet = BookSheet(book: book, editing: false) }
                Button("更新章节") { Task { await container.downloads.refresh([book]); await refreshBooks() } }
            }
        }
    }
}
