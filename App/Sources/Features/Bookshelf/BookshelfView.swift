import SwiftUI
import LegadoCore

struct BookshelfView: View {
    private struct BookSheet: Identifiable {
        let id = UUID()
        let book: BookRow
        let editing: Bool
    }
    @Environment(\.themeColors) private var themeColors
    @Environment(AppContainer.self) private var container
    @State private var model: BookshelfViewModel
    @State private var showingAddURL = false
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var actionError: String?
    @State private var confirmingDelete = false
    @State private var preferences = AppPreferences.shared
    @State private var showingLayout = false
    @State private var showingGroups = false
    @State private var editingGroupID: Int64?
    @State private var showingCacheExport = false
    @State private var detailBook: BookRow?
    @State private var showingDetail = false
    @State private var bookSheet: BookSheet?
    @State private var appliedStartupSettings = false
    @State private var resumeBook: BookRow?
    @State private var showingResume = false

    init(bookshelf: any BookshelfReading, groups: any BookGroupReading, preferences: AppPreferences = .shared) {
        _model = State(initialValue: BookshelfViewModel(bookshelf: bookshelf, groups: groups))
        _preferences = State(initialValue: preferences)
    }

    private var layout: BookshelfLayout { BookshelfLayout(rawValue: preferences.integer("bookshelfLayout")) ?? .list }
    private var folderStyle: Bool { preferences.integer("bookGroupStyle") == 1 }
    private var folderRoot: Bool { folderStyle && model.selectedGroupID == -100 }
    private var margin: Double { Double(max(0, min(40, preferences.integer("bookshelfMargin")))) }
    private var title: String {
        guard folderStyle, !folderRoot, let group = model.groups.first(where: { $0.groupId == model.selectedGroupID }) else { return "书架" }
        return "书架(" + group.groupName + ")"
    }

    var body: some View {
        ScrollViewReader { scroll in
            VStack(spacing: 0) {
                if !folderStyle { groupTabs }
                if selecting { selectionActions }
                shelfHeader
                if let actionError { Text(actionError).foregroundStyle(themeColors.error).font(.system(size: 13)) }
                if let report = container.downloads.refreshReport, !report.failures.isEmpty {
                    Text("已更新 \(report.updated.count) 本，\(report.failures.count) 本失败")
                        .font(.system(size: 13)).foregroundStyle(themeColors.textSecondary)
                }
                if model.isLoading && model.books.isEmpty && !folderRoot {
                    LoadingView()
                } else if let error = model.errorMessage {
                    VStack { Text(error); Button("重试") { Task { await refreshBooks() } } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Color.clear.frame(height: 0).id("bookshelf.top")
                        if model.books.isEmpty && (!folderRoot || model.groups.isEmpty) {
                            Text("书架为空").font(.system(size: 14)).foregroundStyle(themeColors.textSecondary)
                                .frame(maxWidth: .infinity).containerRelativeFrame(.vertical)
                        } else if let columns = layout.columns {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: margin), count: columns), spacing: margin) {
                                shelfItems
                            }.padding(.horizontal, margin + 12).padding(.vertical, margin)
                        } else {
                            LazyVStack(spacing: 0) { shelfItems }.padding(.vertical, 4)
                        }
                    }
                    .accessibilityIdentifier("bookshelf.contents")
                    .refreshable { await updateChapters() }
                    .simultaneousGesture(DragGesture().onEnded { value in
                        if abs(value.translation.width) > 60 && abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                            switchGroup(forward: value.translation.width < 0)
                        }
                    })
                    .overlay(alignment: .trailing) {
                        if preferences.boolean("showBookshelfFastScroller"), !model.books.isEmpty {
                            Menu {
                                ForEach(model.books, id: \.bookUrl) { book in
                                    Button(book.name) { scroll.scrollTo(book.bookUrl, anchor: .top) }
                                }
                            } label: { Image(systemName: "arrow.up.arrow.down").padding(8) }
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: MainTabObserver.reselectedNotification)) { event in
                if event.object as? String == "bookshelf" { scroll.scrollTo("bookshelf.top", anchor: .top) }
            }
        }
        .legadoNavigationTitle(title)
        .toolbar {
            if folderStyle && !folderRoot {
                ToolbarItem(placement: .topBarLeading) { Button { model.selectedGroupID = -100 } label: { Image(systemName: "chevron.left") } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SearchView(container: container) } label: { Label("搜索", systemImage: "magnifyingglass") }
                    .accessibilityIdentifier("bookshelf.search")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("更新目录") { Task { await updateChapters() } }.disabled(container.downloads.isRefreshing)
                    NavigationLink("添加本地") { LocalImportView(database: container.database) }
                    Button("添加网址") { showingAddURL = true }
                    Button(selecting ? "结束管理" : "书架管理") { selecting.toggle(); selected.removeAll() }
                    Button("缓存 / 导出") { showingCacheExport = true }
                    Button("分组管理") { editingGroupID = nil; showingGroups = true }
                    Button("书架布局") { showingLayout = true }
                } label: { Label("书架菜单", systemImage: "ellipsis") }
                .accessibilityIdentifier("bookshelf.menu")
            }
        }
        .task(id: model.selectedGroupID) {
            await refreshBooks()
            if !appliedStartupSettings {
                appliedStartupSettings = true
                if preferences.boolean("defaultToRead"), let book = model.books.max(by: { $0.durChapterTime < $1.durChapterTime }), book.durChapterTime > 0 {
                    resumeBook = book; showingResume = true
                }
                if preferences.boolean("auto_refresh") { await updateChapters() }
            }
        }
        .navigationDestination(isPresented: $showingResume) {
            if let resumeBook, let book = try? DiscoveryStorage.book(resumeBook) {
                MediaReaderDestination(book: book, container: container)
            }
        }
        .onChange(of: preferences.integer("bookshelfSort")) { _, _ in Task { await refreshBooks() } }
        .onChange(of: folderStyle) { _, folders in model.selectedGroupID = folders ? -100 : -1 }
        .sheet(isPresented: $showingLayout) { BookshelfLayoutSettingsView(preferences: preferences) }
        .sheet(isPresented: $showingCacheExport) {
            BookshelfCacheSelectionView(repository: container.bookshelf, downloads: container.downloads)
        }
        .sheet(isPresented: $showingGroups, onDismiss: { Task { await refreshBooks() } }) {
            NavigationStack {
                GroupEditView(repository: container.bookGroups, initialGroupID: editingGroupID)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showingGroups = false } } }
            }
        }
        .navigationDestination(isPresented: $showingDetail) {
            if let detailBook { BookDetailView(book: detailBook, container: container) }
        }
        .sheet(item: $bookSheet, onDismiss: { Task { await refreshBooks() } }) { item in
            NavigationStack {
                Group {
                    if item.editing { BookInfoEditView(book: item.book, repository: container.bookshelf) }
                    else { BookCacheExportView(book: item.book, model: container.downloads) }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { bookSheet = nil } } }
            }
        }
        .sheet(isPresented: $showingAddURL, onDismiss: { Task { await refreshBooks() } }) {
            AddBookURLView(database: container.database, client: container.httpClient, groupID: model.selectedGroupID)
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
        if !appliedStartupSettings { model.selectedGroupID = folderStyle ? -100 : -1 }
        model.folderMode = folderStyle
        model.sort = BookshelfSort(rawValue: preferences.integer("bookshelfSort")) ?? .lastRead
        await model.load()
        selected.formIntersection(Set(model.books.map(\.bookUrl)))
    }

    private func updateChapters() async {
        guard !container.databaseLifecycle.isSuspended else { return }
        if preferences.boolean("onlyUpdateRead") {
            do {
                let books = try await container.bookshelf.all().filter { $0.totalChapterNum - $0.durChapterIndex - 1 <= 0 }
                await container.downloads.refresh(books)
            } catch { actionError = error.localizedDescription }
        } else { await container.downloads.refresh() }
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
            if selected.count == 1, let book = model.books.first(where: { selected.contains($0.bookUrl) }) {
                Button("编辑") { bookSheet = BookSheet(book: book, editing: true) }
            }
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

    @ViewBuilder private var shelfItems: some View {
        if folderRoot {
            ForEach(model.groups, id: \.groupId) { group in
                Button { model.selectedGroupID = group.groupId } label: {
                    BookshelfFolderView(group: group, books: model.groupPreviews[group.groupId] ?? [],
                        count: model.groupCounts[group.groupId] ?? 0, layout: layout)
                }.buttonStyle(.plain).accessibilityIdentifier("bookshelf.folder." + String(group.groupId))
                if layout.columns == nil { themeColors.divider.frame(height: 0.5) }
            }
        }
        ForEach(model.books, id: \.bookUrl) { book in
            bookSummary(book).id(book.bookUrl)
            if layout.columns == nil { themeColors.divider.frame(height: 0.5) }
        }
    }

    private var groupTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(model.groups, id: \.groupId) { group in
                    Text(group.groupName).font(.system(size: 14))
                        .foregroundStyle(group.groupId == model.selectedGroupID ? themeColors.accent : themeColors.textSecondary)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            if group.groupId == model.selectedGroupID { themeColors.accent.frame(height: 2) }
                        }
                        .contentShape(Rectangle())
                        .gesture(LongPressGesture().exclusively(before: TapGesture()).onEnded { action in
                            switch action {
                            case .first: editingGroupID = group.groupId; showingGroups = true
                            case .second: model.selectedGroupID = group.groupId
                            }
                        })
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.selectedGroupID = group.groupId }
                        .accessibilityIdentifier("bookshelf.group." + String(group.groupId))
                }
            }.padding(.horizontal, 16)
        }
    }

    @ViewBuilder private var shelfHeader: some View {
        if preferences.boolean("showBookshelfRecentReading"), let recent = model.books.max(by: { $0.durChapterTime < $1.durChapterTime }), recent.durChapterTime > 0 {
            Button { open(recent) } label: {
                Label("最近阅读：" + recent.name, systemImage: "clock.arrow.circlepath").font(.system(size: 13)).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 6)
        }
        if preferences.boolean("showBookshelfStats") {
            Text("共 \(model.books.count) 本，已读 \(model.books.filter { $0.durChapterTime > 0 }.count) 本")
                .font(.system(size: 13)).foregroundStyle(themeColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
        }
        if preferences.boolean("showWaitUpCount"), container.downloads.isRefreshing {
            Text("等待更新 \(container.downloads.refreshingBookURLs.count) 本").font(.system(size: 13))
        }
    }

    private func switchGroup(forward: Bool) {
        guard let index = model.groups.firstIndex(where: { $0.groupId == model.selectedGroupID }) else { return }
        let next = index + (forward ? 1 : -1)
        if model.groups.indices.contains(next) { model.selectedGroupID = model.groups[next].groupId }
    }

    private func open(_ book: BookRow) { resumeBook = book; showingResume = true }

    private func bookSummary(_ book: BookRow) -> some View {
        HStack(spacing: 4) {
            if selecting {
                Image(systemName: selected.contains(book.bookUrl) ? "checkmark.circle.fill" : "circle").padding(.leading, 8)
            }
            BookshelfBookView(book: book, layout: layout, preferences: preferences,
                loading: container.downloads.refreshingBookURLs.contains(book.bookUrl))
        }
        .contentShape(Rectangle())
        .gesture(LongPressGesture().exclusively(before: TapGesture()).onEnded { action in
            switch action {
            case .first:
                detailBook = book; showingDetail = true
            case .second:
                if selecting {
                    if !selected.insert(book.bookUrl).inserted { selected.remove(book.bookUrl) }
                } else { open(book) }
            }
        })
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open(book) }
        .accessibilityAction(named: Text("书籍详情")) { detailBook = book; showingDetail = true }
        .accessibilityIdentifier("bookshelf.book." + book.bookUrl)
    }
}
