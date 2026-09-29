import SwiftUI
import LegadoCore

struct ExploreView: View {
    let container: AppContainer
    @State private var model = ExploreSourcesViewModel()
    @State private var editingSource: BookSource?
    @State private var showEditor = false
    @State private var deletingSource: BookSource?
    @Environment(\.themeColors) private var colors

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if model.isLoading { LoadingView() }
                    if let error = model.errorMessage {
                        VStack(spacing: 8) {
                            Text(error).foregroundStyle(colors.error)
                            Button("重试") { Task { await model.load(repository: container.bookSources) } }
                                .accessibilityIdentifier("explore.retry")
                        }
                    }
                    ForEach(model.filteredSources, id: \.bookSourceUrl) { source in
                        sourceRow(source).id(source.bookSourceUrl)
                    }
                    if !model.isLoading && model.filteredSources.isEmpty { EmptyText(text: "当前没有发现源！") }
                }.padding(16)
            }
            .legadoNavigationTitle("发现")
            .task { await model.load(repository: container.bookSources) }
            .refreshable { await model.load(repository: container.bookSources) }
            .onChange(of: model.expandedURL) { _, url in
                if let url { proxy.scrollTo(url, anchor: .top) }
            }
            .onChange(of: model.selectedGroup) { _, _ in model.collapse() }
            .onReceive(NotificationCenter.default.publisher(for: MainTabObserver.reselectedNotification)) { event in
                if event.object as? String == "explore" { model.collapse() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("全部") { model.selectedGroup = "" }
                        ForEach(model.groups, id: \.self) { group in Button(group) { model.selectedGroup = group } }
                    } label: { Image(systemName: "folder") }.accessibilityIdentifier("explore.groups")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SourcesView(repository: container.bookSources, replaceRules: container.replaceRules,
                            httpClient: ImportHttpClient(), sourceLogin: container.sourceLogin, sourceChecker: container.sourceChecker)
                    } label: { Image(systemName: "gearshape") }.accessibilityLabel("书源管理")
                }
            }
            .sheet(isPresented: $showEditor) {
                BookSourceEditView(source: editingSource, repository: container.bookSources, client: container.httpClient,
                    login: container.sourceLogin, checker: container.sourceChecker) { await model.load(repository: container.bookSources) }
            }
            .confirmationDialog("删除书源？", isPresented: Binding(get: { deletingSource != nil }, set: { if !$0 { deletingSource = nil } })) {
                Button("删除", role: .destructive) {
                    if let source = deletingSource { Task { await model.delete(source, repository: container.bookSources) } }
                    deletingSource = nil
                }
            }
        }
    }

    private func sourceRow(_ source: BookSource) -> some View {
        let expanded = model.expandedURL == source.bookSourceUrl
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Task { await model.toggle(source, client: container.httpClient, stateRepository: states) }
            } label: {
                HStack {
                    Text(source.bookSourceName ?? "未命名书源").font(.system(size: 16))
                    Spacer()
                    if expanded && model.kindsLoading { ProgressView().frame(width: 20, height: 20) }
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").frame(width: 20, height: 20)
                }.padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("explore.source." + (source.bookSourceUrl ?? ""))
            .contextMenu {
                Button("编辑") { editingSource = source; showEditor = true }
                Button("置顶") { Task { await model.moveToTop(source, repository: container.bookSources) } }
                NavigationLink("登录") { SourceLoginDestination(source: source, service: container.sourceLogin) }
                NavigationLink("搜索") { search(source) }
                Button("刷新") { Task { await model.refresh(source, client: container.httpClient, stateRepository: states) } }
                Button("删除", role: .destructive) { deletingSource = source }
            }
            if expanded {
                LabelFlowLayout() {
                    ForEach(Array(model.kinds.enumerated()), id: \.offset) { _, kind in
                        kindView(kind, source: source)
                    }
                }.padding(3).padding(.top, 8)
            }
        }.padding(.bottom, expanded ? 6 : 0).background(colors.card, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func kindView(_ kind: ExploreKind, source: BookSource) -> some View {
        let title = model.controlNames[kind.title] ?? kind.title
        if kind.type == "url", !kind.isHeading {
            NavigationLink {
                ExploreBookListView(source: source, kind: kind, container: container, kinds: model.kinds)
            } label: { Text(title).font(.system(size: 14)).padding(6).background(colors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3)) }
                .accessibilityIdentifier("explore.kind." + kind.title)
        } else if kind.type == "text" {
            ExploreTextControl(title: title, value: Binding(get: { model.controlValues[kind.title] ?? "" }, set: { model.controlValues[kind.title] = $0 })) {
                await model.act(kind, source: source, client: container.httpClient, stateRepository: states)
            }
        } else if kind.type == "select" {
            Picker(title, selection: Binding(get: { model.controlValues[kind.title] ?? "" }, set: { value in
                model.controlValues[kind.title] = value
                Task { await model.act(kind, source: source, client: container.httpClient, stateRepository: states) }
            })) { ForEach(kind.chars, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
        } else if kind.type == "button" || kind.type == "toggle" {
            Button((kind.type == "toggle" ? (model.controlValues[kind.title] ?? "") : "") + title) {
                if kind.type == "toggle", !kind.chars.isEmpty {
                    let index = kind.chars.firstIndex(of: model.controlValues[kind.title] ?? "") ?? -1
                    model.controlValues[kind.title] = kind.chars[(index + 1) % kind.chars.count]
                }
                Task { await model.act(kind, source: source, client: container.httpClient, stateRepository: states) }
            }.buttonStyle(.bordered).accessibilityIdentifier("explore.control." + kind.title)
        } else { Text(title).font(.system(size: 14)).foregroundStyle(colors.textSecondary).padding(6) }
    }

    private var states: SourceStateRepository { SourceStateRepository(database: container.database) }
    private func search(_ source: BookSource) -> some View {
        let search = SearchViewModel(sources: container.bookSources, client: container.httpClient)
        search.scope = SearchScope(value: (source.bookSourceName ?? "").replacingOccurrences(of: ":", with: "") + "::" + (source.bookSourceUrl ?? ""))
        return SearchView(container: container, model: search)
    }
}

private struct ExploreTextControl: View {
    let title: String
    @Binding var value: String
    let action: () async -> Void
    @State private var pending: Task<Void, Never>?
    var body: some View {
        TextField(title, text: $value).textFieldStyle(.roundedBorder).frame(width: 180)
            .accessibilityIdentifier("explore.input." + title)
            .onChange(of: value) { _, _ in
                pending?.cancel()
                pending = Task {
                    do { try await Task.sleep(for: .milliseconds(600)); try Task.checkCancellation(); await action() }
                    catch is CancellationError { }
                    catch { AppLogStore.shared.append(error.localizedDescription) }
                }
            }.onDisappear { pending?.cancel() }
    }
}
