import SwiftUI
import LegadoCore

struct SearchView: View {
    @State private var model: SearchViewModel
    @State private var preferences: AppPreferences
    @State private var showingScope = false
    @State private var showingSources = false
    @State private var showingFailures = false
    @State private var showingFilter = false
    @State private var filterInput = ""
    @State private var loadedPreferences = false
    @Environment(\.themeColors) private var colors
    private let container: AppContainer
    private let onRead: ((Book, Int) -> Void)?

    init(container: AppContainer, onRead: ((Book, Int) -> Void)? = nil,
         model: SearchViewModel? = nil, preferences: AppPreferences? = nil) {
        self.container = container
        self.onRead = onRead
        _preferences = State(initialValue: preferences ?? .shared)
        _model = State(initialValue: model ?? SearchViewModel(sources: container.bookSources, client: container.httpClient,
            keywords: SearchKeywordRepository(database: container.database), bookshelf: container.bookshelf,
            records: container.readProgress, concurrencyLimit: UserDefaults.standard.object(forKey: "threadCount") as? Int ?? 32))
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isSearching {
                RefreshProgressBar(progress: Double(model.completedSources) / Double(max(1, model.totalSources)))
            }
            if let error = model.userError {
                ErrorBanner(error: error, dismiss: model.dismissError) { action in
                    if action == .manageSources { showingSources = true }
                    if action == .retry { startSearch() }
                }.padding(8)
            }
            if model.availableSources.isEmpty {
                Button("请先导入书源") { showingSources = true }.padding().accessibilityIdentifier("search.importSources")
            }
            if !model.hasSearched {
                inputHelp
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.visibleResults) { result in
                            NavigationLink {
                                BookDetailView(results: result.sources, container: container, onRead: onRead)
                            } label: {
                                SearchResultRow(book: result.book, sourceCount: result.sources.count,
                                    isOnShelf: model.isOnShelf(result.book),
                                    hasRead: preferences.boolean("showSearchReadRecord") && model.hasRead(result.book))
                            }.buttonStyle(.plain).accessibilityIdentifier("search.result." + result.id.name + "|" + result.id.author)
                            colors.divider.frame(height: 0.5)
                        }
                        if model.visibleResults.isEmpty && !model.isSearching {
                            Text("暂无搜索结果").foregroundStyle(colors.textSecondary).padding(.top, 80)
                        }
                        if model.failedSources > 0 {
                            DisclosureGroup("\(model.failedSources) 个书源搜索失败或超时", isExpanded: $showingFailures) {
                                ForEach(model.failures) { failure in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(failure.name).font(.headline)
                                        Text(failure.error.message).font(.callout).textSelection(.enabled)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                                }
                            }.padding().accessibilityIdentifier("search.failures")
                        }
                        Color.clear.frame(height: 100)
                    }
                }.scrollDismissesKeyboard(.interactively)
            }
        }
        .legadoNavigationTitle("搜索")
        .toolbar {
            ToolbarItem(placement: .principal) {
                CapsuleSearchField(text: Binding(get: { model.query }, set: { model.query = $0; model.editQuery() }),
                    prompt: "书名或作者", onSubmit: startSearch, autofocus: true, navigationColors: true)
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: .infinity).accessibilityIdentifier("search.input")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("精准搜索", isOn: Binding(get: { model.precisionSearch }, set: {
                        model.precisionSearch = $0; preferences.set("precisionSearch", .boolean($0))
                        if model.hasSearched { startSearch() }
                    }))
                    Toggle("标识读过的书籍", isOn: Binding(get: { preferences.boolean("showSearchReadRecord") }, set: {
                        preferences.set("showSearchReadRecord", .boolean($0))
                    }))
                    Button("搜索结果屏蔽词") { filterInput = model.filterWords; showingFilter = true }
                    NavigationLink("书源管理") {
                        SourcesView(repository: container.bookSources, replaceRules: container.replaceRules,
                            httpClient: ImportHttpClient(), sourceLogin: container.sourceLogin, sourceChecker: container.sourceChecker)
                    }
                    Button("多分组 / 书源") { showingScope = true }
                    NavigationLink("日志") { AppLogView() }
                } label: { Label("搜索菜单", systemImage: "ellipsis") }
                .accessibilityIdentifier("search.menu")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                if model.hasSearched {
                    Text("已搜 \(model.completedSources) / \(model.totalSources)")
                        .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(colors.card, in: Capsule())
                        .accessibilityIdentifier("search.progress")
                }
                Button {
                    if model.isSearching { model.cancel() } else { startSearch() }
                } label: {
                    Image(systemName: model.isSearching ? "stop.fill" : "magnifyingglass")
                        .font(.system(size: 23)).frame(width: 56, height: 56)
                        .foregroundStyle(colors.onAccent).background(colors.accent, in: Circle())
                }
                .accessibilityLabel(model.isSearching ? "停止" : "开始")
                .accessibilityIdentifier("search.startStop")
                .disabled(!model.isSearching && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(16)
        }
        .navigationDestination(isPresented: $showingSources) {
            SourcesView(repository: container.bookSources, replaceRules: container.replaceRules,
                httpClient: container.httpClient, sourceLogin: container.sourceLogin, sourceChecker: container.sourceChecker)
        }
        .sheet(isPresented: $showingScope) {
            SearchScopeView(sources: model.availableSources, scope: model.scope) { scope in
                model.scope = scope
                saveScope()
                if model.hasSearched { startSearch() }
            }
        }
        .sheet(isPresented: $showingFilter) {
            NavigationStack {
                Form {
                    Section("每行一个词，匹配书名、作者或分类") {
                        TextEditor(text: $filterInput).frame(minHeight: 180).accessibilityIdentifier("search.filter.input")
                    }
                }
                .legadoNavigationTitle("搜索结果屏蔽词")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showingFilter = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确定") {
                            model.filterWords = filterInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            preferences.set("searchResultFilter", .string(model.filterWords)); showingFilter = false
                        }
                    }
                }
            }
        }
        .task {
            if !loadedPreferences {
                model.precisionSearch = preferences.boolean("precisionSearch")
                model.filterWords = preferences.string("searchResultFilter")
                model.scope = SearchScope(value: preferences.string("searchScope"))
                loadedPreferences = true
            }
            await model.loadInputHelp()
        }
        .onDisappear { model.cancel() }
    }

    private var inputHelp: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("书架").font(.system(size: 14, weight: .medium))
                if model.matchingShelf.isEmpty { Text("没有匹配的书架书籍").font(.system(size: 12)).foregroundStyle(colors.textSecondary) }
                LabelFlowLayout {
                    ForEach(model.matchingShelf, id: \.bookUrl) { book in
                        NavigationLink { BookDetailView(book: book, container: container, onRead: onRead) } label: { capsule(book.name) }
                            .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("搜索历史").font(.system(size: 14, weight: .medium))
                    Spacer()
                    Button("清空") { Task { await model.clearHistory() } }.font(.system(size: 12)).disabled(model.history.isEmpty)
                        .accessibilityIdentifier("search.history.clear")
                }
                LabelFlowLayout {
                    ForEach(model.matchingHistory, id: \.word) { keyword in
                        capsule(keyword.word)
                            .contentShape(Capsule())
                            .gesture(LongPressGesture().exclusively(before: TapGesture()).onEnded { action in
                                switch action {
                                case .first: Task { await model.deleteHistory(keyword) }
                                case .second: model.query = keyword.word; startSearch()
                                }
                            })
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { model.query = keyword.word; startSearch() }
                            .accessibilityAction(named: Text("删除")) { Task { await model.deleteHistory(keyword) } }
                            .accessibilityIdentifier("search.history." + keyword.word)
                    }
                }
                Text(model.scope.display).font(.system(size: 12)).foregroundStyle(colors.textSecondary)
            }.padding(16).padding(.bottom, 80).frame(maxWidth: .infinity, alignment: .leading)
        }.scrollDismissesKeyboard(.interactively)
    }

    private func capsule(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).lineLimit(1).foregroundStyle(colors.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 7).background(colors.card, in: Capsule())
            .overlay { Capsule().stroke(colors.divider, lineWidth: 0.5) }
    }

    private func saveScope() {
        preferences.set("searchScope", .string(model.scope.value))
        preferences.set("searchGroup", .string(model.scope.sourceURL == nil && model.scope.groups.count == 1 ? model.scope.value : ""))
    }

    private func startSearch() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        Task {
            await model.search(model.query)
            saveScope()
            for failure in model.sourceFailures { AppLogStore.shared.append(failure) }
        }
    }
}
