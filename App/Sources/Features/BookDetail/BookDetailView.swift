import SwiftUI
import LegadoCore

struct BookDetailView: View {
    @State private var model: BookDetailViewModel
    @State private var confirmingShelf = false
    @State private var expandedIntro = false
    @State private var sheet: DetailSheet?
    @State private var reading: ReaderDestination?
    @State private var groups: [BookGroupRow] = []
    @State private var message: String?
    @State private var actionRunning = false
    @Environment(\.themeColors) private var colors
    private let container: AppContainer
    private let onRead: ((Book, Int) -> Void)?

    init(results: [SearchBook], container: AppContainer, onRead: ((Book, Int) -> Void)? = nil) {
        self.container = container
        self.onRead = onRead
        _model = State(initialValue: BookDetailViewModel(results: results, sources: container.bookSources,
            bookshelf: container.bookshelf, client: container.httpClient))
    }

    init(book: BookRow, container: AppContainer, onRead: ((Book, Int) -> Void)? = nil) {
        self.container = container
        self.onRead = onRead
        var result = SearchBook()
        result.bookUrl = book.bookUrl; result.origin = book.origin; result.originName = book.originName
        result.name = book.name; result.author = book.author; result.coverUrl = book.customCoverUrl ?? book.coverUrl
        result.latestChapterTitle = book.latestChapterTitle; result.kind = book.kind; result.intro = book.customIntro ?? book.intro
        let stored = try? DiscoveryStorage.book(book)
        _model = State(initialValue: BookDetailViewModel(results: [result], sources: container.bookSources,
            bookshelf: container.bookshelf, client: container.httpClient, initialBook: stored))
    }

    private var title: String { model.book?.name ?? model.results.first?.name ?? "书籍详情" }
    private var cover: String? { model.book?.customCoverUrl ?? model.book?.coverUrl ?? model.results.first?.coverUrl }
    private var intro: String { model.book?.customIntro ?? model.book?.intro ?? "暂无简介" }
    private var groupNames: String {
        let selected = groups.filter { $0.groupId > 0 && (model.book?.group ?? 0) & $0.groupId != 0 }.map(\.groupName)
        return selected.isEmpty ? "未分组" : selected.joined(separator: "、")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(title).font(.system(size: 18)).fixedSize(horizontal: true, vertical: false)
                    }.padding(.bottom, 8)
                    LabelsBar(labels: (model.book?.kind ?? "").components(separatedBy: CharacterSet(charactersIn: ",，\n"))
                        .filter { !$0.isEmpty }).padding(.bottom, 12)
                    infoRow("person", text: model.book?.author ?? "未知作者")
                    infoRow("tray.full", text: model.book?.originName ?? "本地书籍", action: "换源") { sheet = .sources }
                    infoRow("clock.arrow.circlepath", text: model.book?.latestChapterTitle ?? "暂无最新章节")
                    infoRow("folder", text: groupNames, action: "设置分组") { sheet = .groups }
                    HStack {
                        Image(systemName: "list.bullet").font(.system(size: 18)).frame(width: 24)
                        Text("目录 · \(model.book?.totalChapterNum ?? 0) 章").font(.system(size: 13))
                        Spacer()
                        if let book = model.book {
                            NavigationLink("查看目录") {
                                TocView(book: book, source: model.source ?? BookSource(), container: container) { index in
                                    Task { await read(index) }
                                }
                            }.font(.system(size: 13)).foregroundStyle(colors.accent)
                        }
                    }.frame(minHeight: 40)
                    Text(intro).font(.system(size: 14)).lineSpacing(5)
                        .lineLimit(expandedIntro ? nil : 4).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16)
                    Button(expandedIntro ? "收起" : "展开") { expandedIntro.toggle() }
                        .font(.system(size: 14)).frame(maxWidth: .infinity, minHeight: 48)
                        .accessibilityIdentifier("detail.intro.toggle")
                    Divider()
                    if let error = model.errorMessage { errorView(error) }
                    if let message { Text(message).font(.footnote).padding(.vertical, 8) }
                }.padding(.horizontal, 16)
            }.padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .overlay(alignment: .top) { if model.isLoading || actionRunning { RefreshProgressBar() } }
        .legadoNavigationTitle("书籍详情")
        .onReceive(NotificationCenter.default.publisher(for: .init("Legado.script.refresh"))) { notification in
            if notification.object as? String == "refreshBookInfo", !model.isLoading { Task { await model.load() } }
        }
        .toolbar { detailToolbar }
        .sheet(item: $sheet, onDismiss: { Task { await reload() } }) { destination in
            NavigationStack { sheetContent(destination).toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { sheet = nil } } } }
        }
        .navigationDestination(item: $reading) { destination in
            ReaderView(destination: destination, database: container.database, client: container.httpClient)
        }
        .confirmationDialog(model.isOnBookshelf ? "删除这本书？" : "将这本书加入书架？", isPresented: $confirmingShelf, titleVisibility: .visible) {
            Button(model.isOnBookshelf ? "删除书籍" : "放入书架", role: model.isOnBookshelf ? .destructive : nil) {
                Task { await model.toggleBookshelf() }
            }
        }
        .task {
            if model.book == nil { await model.load() }
            await reload()
        }
    }

    private var header: some View {
        ZStack(alignment: .top) {
            GeometryReader { geometry in
                ZStack {
                    colors.primary.opacity(0.3)
                    if let cover { RemoteImage(url: cover, origin: model.book?.origin, book: model.book)
                        .frame(width: geometry.size.width, height: 168).blur(radius: 20) }
                }.frame(height: 168).clipped()
                DetailCoverArc().fill(colors.background).frame(height: 78).offset(y: 90)
            }
            ZStack {
                colors.card
                if let cover { RemoteImage(url: cover, origin: model.book?.origin, book: model.book, placeholderTitle: title) }
                else { Text(String(title.prefix(1))).font(.system(size: 36)).foregroundStyle(colors.textSecondary) }
            }.frame(width: 110, height: 160).clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(colors.isEInk ? 0 : 0.15), radius: 4, y: 2).padding(.top, 16)
        }.frame(height: 192)
    }

    private func infoRow(_ icon: String, text: String, action: String? = nil, perform: @escaping () -> Void = {}) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 18)).frame(width: 24)
            Text(text).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 8)
            if let action { Button(action, action: perform).font(.system(size: 13)).foregroundStyle(colors.accent) }
        }.frame(minHeight: 40)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(model.isOnBookshelf ? "删除书籍" : "放入书架") {
                let key = model.isOnBookshelf ? "bookInfoDeleteAlert" : "showAddToShelfAlert"
                if AppPreferences.shared.boolean(key) { confirmingShelf = true }
                else { Task { await model.toggleBookshelf() } }
            }.foregroundStyle(colors.accent).frame(maxWidth: .infinity, minHeight: 48)
                .background(colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            if let book = model.book, book.mediaKind != .text {
                NavigationLink { MediaReaderDestination(book: book, container: container) } label: { readLabel }
            } else {
                Button { Task { await read(nil) } } label: { readLabel }.accessibilityIdentifier("detail.read")
            }
        }.font(.system(size: 15)).buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 8)
            .background(colors.menu).disabled(model.book == nil || model.isLoading || model.isSaving || actionRunning)
    }

    private var readLabel: some View {
        Text("阅读").foregroundStyle(colors.onAccent).frame(maxWidth: .infinity, minHeight: 48)
            .background(colors.accent, in: RoundedRectangle(cornerRadius: 8))
    }

    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading) {
            Text(error).foregroundStyle(colors.error)
            Button("重试") { Task { await model.load() } }
        }.font(.footnote).padding(.vertical, 8)
    }

    private func reload() async {
        await model.refreshShelfState()
        do { groups = try await container.bookGroups.list() }
        catch { message = error.presentation(operation: "读取书籍分组", subject: title)?.displayText }
    }

    private func read(_ index: Int?) async {
        guard let book = await model.prepareForReading(database: container.database) else { return }
        if let onRead { onRead(book, index ?? book.durChapterIndex) }
        else { reading = ReaderDestination(bookURL: book.bookUrl ?? "", chapterIndex: index) }
    }
}

private struct DetailCoverArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height), control: CGPoint(x: rect.midX, y: -rect.height))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height)); path.closeSubpath()
        return path
    }
}

private enum DetailSheet: String, Identifiable {
    case sources, groups, edit, sourceVariable, bookVariable, task, upload
    var id: String { rawValue }
}

private extension BookDetailView {
    @ToolbarContentBuilder var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.source?.customButton == true {
                Button { runAction("执行书源定制按钮") { _ = try await callback("clickCustomButton") } } label: { Image(systemName: "star") }
                    .accessibilityLabel("定制按钮").disabled(actionRunning)
            }
            Button { sheet = .edit } label: { Image(systemName: "pencil") }.accessibilityLabel("编辑")
            ShareLink(item: model.book?.bookUrl ?? "") { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享")
            Menu {
                if let book = model.book, LocalBook.isLocal(book) {
                    Button("上传 WebDav") { sheet = .upload }
                }
                Button("刷新", systemImage: "arrow.clockwise") { Task { await model.load() } }.disabled(model.source == nil)
                if model.isOnBookshelf, model.source != nil, model.book?.canUpdate == true {
                    Button("生成更新任务") { sheet = .task }
                }
                if let source = model.source, !(source.loginUrl ?? "").isEmpty {
                    NavigationLink("登录") { SourceLoginDestination(source: source, service: container.sourceLogin) }
                }
                Button("置顶") { Task { await model.moveToTop() } }.disabled(!model.isOnBookshelf)
                if model.source != nil { Button("设置源变量") { sheet = .sourceVariable } }
                Button("设置书籍变量") { sheet = .bookVariable }
                Button("拷贝书籍 URL") { runAction("拷贝书籍网址") { if try await !callback("clickCopyBookUrl") { UIPasteboard.general.string = model.book?.bookUrl } } }
                Button("拷贝目录 URL") { runAction("拷贝目录网址") { if try await !callback("clickCopyTocUrl") { UIPasteboard.general.string = model.book?.tocUrl } } }
                if model.source != nil {
                    Toggle("允许更新", isOn: Binding(get: { model.book?.canUpdate ?? true }, set: { value in Task { await model.setCanUpdate(value) } }))
                }
                if let book = model.book, LocalBook.fileURL(book)?.pathExtension.lowercased() == "txt" {
                    Toggle("拆分超长章节", isOn: Binding(get: { model.book?.readConfig?.splitLongChapter ?? true }, set: { value in
                        runAction("保存章节拆分设置") {
                            await model.setSplitLongChapter(value)
                            if let error = model.errorMessage { throw NSError(domain: "BookDetail", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
                            guard let url = model.book?.bookUrl else { return }
                            try await container.database.write { db in try db.execute(sql: "DELETE FROM chapters WHERE bookUrl = ?", arguments: [url]) }
                        }
                    }))
                }
                Toggle("删除提醒", isOn: Binding(get: { AppPreferences.shared.boolean("bookInfoDeleteAlert") },
                    set: { AppPreferences.shared.set("bookInfoDeleteAlert", .boolean($0)) }))
                Button("清理缓存") { runAction("清理书籍缓存") { try await clearCache() } }
                NavigationLink("日志") { AppLogView() }
            } label: { Image(systemName: "ellipsis") }.accessibilityLabel("更多")
        }
    }

    @ViewBuilder func sheetContent(_ destination: DetailSheet) -> some View {
        switch destination {
        case .sources:
            BookSourceSwitchView(book: model.book, initial: model.results, container: container) { result in
                await model.selectResult(result); sheet = nil
            }
        case .groups:
            BookDetailGroupView(repository: container.bookGroups, selected: model.book?.group ?? 0) { mask in
                await model.setGroups(mask); sheet = nil
            }
        case .edit:
            BookDetailEditDestination(model: model, repository: container.bookshelf)
        case .bookVariable:
            DetailTextEditor(title: "设置书籍变量", initial: model.book?.variable ?? "") { value in
                await model.setVariable(value)
                if let error = model.errorMessage { throw NSError(domain: "BookDetail", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
            }
        case .sourceVariable:
            SourceVariableEditor(source: model.source?.bookSourceUrl ?? "", repository: SourceStateRepository(database: container.database))
        case .task:
            if let book = model.book { BookUpdateTaskEditor(book: book, repository: AutoTaskRuleRepository(database: container.database)) }
        case .upload:
            if let book = model.book { LocalBookUploadView(book: book, client: container.httpClient) }
        }
    }

    func runAction(_ operation: String, _ action: @escaping () async throws -> Void) {
        guard !actionRunning else { return }
        actionRunning = true; message = nil
        Task {
            defer { actionRunning = false }
            do { try await action() }
            catch { message = error.presentation(operation: operation, subject: title)?.displayText
                AppLogStore.shared.append("Book detail: " + String(reflecting: error)) }
        }
    }

    func callback(_ event: String) async throws -> Bool {
        guard let source = model.source, let book = model.book else { return false }
        let client = container.httpClient
        let task = Task.detached { try SourceCallback.run(source: source, book: book, event: event, client: client) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func clearCache() async throws {
        guard let book = model.book, try await !callback("clickClearCache") else { return }
        let rows = try await container.chapters.list(bookUrl: book.bookUrl ?? "")
        let chapters = try rows.map { try JSONDecoder().decode(BookChapter.self, from: JSONEncoder().encode($0)) }
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Legado/ReaderCache", isDirectory: true)
        try await Task.detached { try BookHelp.clearCache(directory: directory, book: book, chapters: chapters) }.value
        message = "缓存已清理"
    }
}
