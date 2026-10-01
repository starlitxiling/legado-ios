import SwiftUI
import LegadoCore

struct SourcesView: View {
    @State private var model: SourcesViewModel
    @State private var importEntry: ManagementImportEntry?
    @State private var editor: SourceEditorRequest?
    @State private var shareText = ""
    @State private var showShare = false
    @State private var groupText = ""
    @State private var showGroup = false
    @State private var removingGroup = false
    @State private var selecting = false
    @State private var showsGroups = false
    @State private var showsQR = false
    @AppStorage("showSourceCheckState") private var showsStatus = true
    @AppStorage("sourceGroupByDomain") private var groupByDomain = false
    @AppStorage("blockSourceNavigation") private var blockNavigation = false
    @Environment(\.themeColors) private var colors
    private let initialImportURL: String?
    private let repository: BookSourceRepository
    private let replaceRules: ReplaceRuleRepository
    private let httpClient: any ResponseLimitedHttpClient
    private let sourceLogin: SourceLogin
    private let sourceChecker: SourceChecker

    init(repository: BookSourceRepository, replaceRules: ReplaceRuleRepository,
         httpClient: any ResponseLimitedHttpClient, sourceLogin: SourceLogin, sourceChecker: SourceChecker, initialImportURL: String? = nil) {
        let model = SourcesViewModel(repository: repository, httpClient: httpClient)
        model.useSourceReplacement = UserDefaults.standard.bool(forKey: "importReplaceSource")
        _model = State(initialValue: model)
        self.initialImportURL = initialImportURL
        self.replaceRules = replaceRules
        self.repository = repository
        self.httpClient = httpClient
        self.sourceLogin = sourceLogin
        self.sourceChecker = sourceChecker
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if showsStatus {
                Picker("校验状态", selection: $model.statusFilter) {
                    ForEach(SourceStatusFilter.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal, 12).frame(minHeight: 48)
            }
            List {
                if let error = model.errorMessage, importEntry == nil {
                    Text(error).foregroundStyle(.red)
                    Button("重试") { Task { await model.load() } }
                }
                if groupByDomain {
                    ForEach(domains, id: \.self) { domain in
                        Section(domain) { sourceRows(model.filteredSources.filter { host($0) == domain }) }
                    }
                } else { sourceRows(model.filteredSources) }
            }.listStyle(.plain)
        }
        .overlay {
            if model.isBusy { ProgressView() }
            else if model.filteredSources.isEmpty && model.errorMessage == nil {
                ContentUnavailableView("没有书源", systemImage: "tray", description: Text("导入书源，或调整搜索和分组条件。"))
                    .allowsHitTesting(false)
            }
        }
        .legadoNavigationTitle("书源")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting {
                SelectActionBar(selectedCount: model.selectedURLs.count, totalCount: model.filteredSources.count,
                    onSelectAll: { model.selectedURLs = Set(model.filteredSources.map(\.bookSourceUrl)) }) {
                    Button("反选") { model.selectedURLs = Set(model.filteredSources.map(\.bookSourceUrl)).subtracting(model.selectedURLs) }
                    Button("启用") { Task { await model.batchEnabled(true) } }.disabled(model.selectedURLs.isEmpty)
                    Menu { selectionActions } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .refreshable { await model.load() }
        .toolbar {
            ToolbarItem(placement: .principal) { CapsuleSearchField(text: $model.keyword, prompt: "书源 / group:分组", navigationColors: true) }
            ToolbarItem(placement: .topBarTrailing) { Button(selecting ? "完成" : "多选") { selecting.toggle(); if !selecting { model.selectedURLs = [] } } }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("分组管理") { showsGroups = true }
                    ForEach(SourceFilter.allCases) { filter in
                        Button(filter.rawValue) { model.filter = filter; model.keyword = ""; model.selectedGroup = nil }
                    }
                    ForEach(model.groups, id: \.self) { group in
                        Button(group) { model.keyword = "group:" + group; model.filter = .all; model.selectedGroup = nil }
                    }
                    Picker("排序", selection: $model.sort) {
                        ForEach(SourceSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("反序", isOn: Binding(get: { !model.ascending }, set: { model.ascending = !$0 }))
                } label: { Label(model.selectedGroup ?? "分组", systemImage: "line.3.horizontal.decrease.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("从 URL 导入") { importEntry = .url }
                    Button("新建书源") { editor = SourceEditorRequest(source: nil) }
                    Button("新建 JS 书源") {
                        var source = BookSource(); source.mainJs = "function search(key, page) { return []; }"
                        editor = SourceEditorRequest(source: source)
                    }
                    Button("二维码导入") { showsQR = true }
                    Toggle("按域名分组显示", isOn: $groupByDomain)
                    Toggle("显示校验状态", isOn: $showsStatus)
                    Toggle("禁止网页跳转", isOn: $blockNavigation)
                    Link("帮助", destination: URL(string: "https://github.com/gedoor/legado/wiki")!)
                    Button("导出当前列表") { export(selected: nil) }
                    if !model.selectedURLs.isEmpty { selectionActions }
                    Button("从文件导入") { importEntry = .file }
                    Button("从剪贴板导入") { importEntry = .clipboard }
                    NavigationLink("Cookie 管理") { CookieManagementView(service: sourceLogin) }
                    NavigationLink("批量校验") {
                        CheckSourceView(sources: model.filteredSources.compactMap(loginSource), checker: sourceChecker)
                    }
                    NavigationLink("替换规则") {
                        ReplaceRulesView(repository: replaceRules, httpClient: httpClient)
                    }
                } label: { Label("书源工具", systemImage: "ellipsis.circle") }
                .disabled(model.isBusy)
            }
        }
        .sheet(item: $importEntry, onDismiss: { model.cancelImport() }) { entry in
            SourceImportSheet(title: "书源", entry: entry, preview: model.importPreview,
                              isBusy: model.isBusy, errorMessage: model.errorMessage,
                              prepareText: { await model.prepareImport(text: $0) },
                              prepareURL: { await model.prepareImport(url: $0) },
                              confirm: {
                                  await model.confirmImport()
                                  return model.importPreview == nil && model.errorMessage == nil
                              }, cancel: { model.cancelImport() }, selectedIDs: $model.selectedImportURLs, group: $model.importGroup, keepEnable: $model.keepEnable, sourceReplacement: $model.useSourceReplacement)
        }
        .task {
            await model.load()
            model.importGroup = UserDefaults.standard.string(forKey: "importSourceGroup") ?? ""
            if let initialImportURL { importEntry = .url; await model.prepareImport(url: initialImportURL) }
        }
        .onChange(of: model.importGroup) { _, value in UserDefaults.standard.set(value, forKey: "importSourceGroup") }
        .sheet(isPresented: $showsQR) {
            SourceQRImportView { text in
                showsQR = false
                importEntry = .url
                Task {
                    if text.hasPrefix("http://") || text.hasPrefix("https://") { await model.prepareImport(url: text) }
                    else if let url = URL(string: text), let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "src" || $0.name == "url" })?.value { await model.prepareImport(url: query) }
                    else { await model.prepareImport(text: text) }
                }
            }
        }
        .sheet(isPresented: $showsGroups) { SourceGroupManagementView(model: model) }
        .onChange(of: model.useSourceReplacement) { _, value in UserDefaults.standard.set(value, forKey: "importReplaceSource") }
        .sheet(item: $editor) { request in
            NavigationStack {
                BookSourceEditView(source: request.source, repository: repository, client: httpClient,
                    login: sourceLogin, checker: sourceChecker, onSave: { await model.load() })
            }
        }
        .sheet(isPresented: $showShare) { NavigationStack { SourceJSONShareView(text: shareText).sheetCloseButton { showShare = false } } }
        .alert(removingGroup ? "移除分组" : "添加分组", isPresented: $showGroup) {
            TextField("分组名称，多个名称用逗号分隔", text: $groupText)
            Button("取消", role: .cancel) {}
            Button("确定") { Task { await model.changeGroup(groupText, removing: removingGroup) } }
        }
    }

    private func host(_ row: BookSourceRow) -> String { URL(string: row.bookSourceUrl)?.host ?? "其他" }
    private var domains: [String] { Set(model.filteredSources.map(host)).sorted() }

    @ViewBuilder private func sourceRows(_ rows: [BookSourceRow]) -> some View {
        ForEach(rows, id: \.bookSourceUrl) { source in
            if model.sort == .custom && !selecting {
                sourceRow(source).draggable(source.bookSourceUrl)
                    .dropDestination(for: String.self) { items, _ in
                        guard let first = items.first else { return false }
                        Task { await model.reorder(first, before: source.bookSourceUrl) }; return true
                    }
            } else { sourceRow(source) }
        }
    }

    private func sourceRow(_ source: BookSourceRow) -> some View {
        HStack(spacing: 8) {
            if selecting {
                Button {
                    if model.selectedURLs.contains(source.bookSourceUrl) { model.selectedURLs.remove(source.bookSourceUrl) }
                    else { model.selectedURLs.insert(source.bookSourceUrl) }
                } label: { Image(systemName: model.selectedURLs.contains(source.bookSourceUrl) ? "checkmark.square.fill" : "square") }
                .accessibilityLabel("选择 " + source.bookSourceName)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(source.bookSourceName.isEmpty ? "未命名书源" : source.bookSourceName).font(.body).lineLimit(2)
                    if !(source.mainJs ?? "").isEmpty { Text("JS").font(.caption2).foregroundStyle(colors.accent) }
                }
                Text("书架使用 \(model.metadata[source.bookSourceUrl]?.usageCount ?? 0)").font(.caption).foregroundStyle(colors.textSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle("启用 " + source.bookSourceName, isOn: Binding(get: { source.enabled }, set: { enabled in Task { await model.setEnabled(source, enabled: enabled) } }))
                .labelsHidden().scaleEffect(0.8).fixedSize()
            Button { edit(source) } label: { Image(systemName: "pencil").frame(width: 36, height: 36) }.accessibilityLabel("编辑 " + source.bookSourceName)
            Menu { rowActions(source) } label: {
                Image(systemName: "ellipsis").frame(width: 36, height: 36)
                    .overlay(alignment: .topTrailing) {
                        if source.enabledExplore && !(source.exploreUrl ?? "").isEmpty { Circle().fill(colors.discoveryDot).frame(width: 8, height: 8) }
                    }
            }.accessibilityLabel("更多 " + source.bookSourceName)
        }.buttonStyle(.borderless).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .disabled(model.isBusy).contextMenu { rowActions(source) }
            .swipeActions { Button("删除", role: .destructive) { Task { await model.delete(source) } } }
    }

    @ViewBuilder private func rowActions(_ source: BookSourceRow) -> some View {
        Button("编辑") { edit(source) }
        Button("置顶") { Task { await model.move(selected: [source.bookSourceUrl], toTop: true) } }
        Button("置底") { Task { await model.move(selected: [source.bookSourceUrl], toTop: false) } }
        Button(source.enabledExplore ? "禁用发现" : "启用发现") {
            model.selectedURLs = [source.bookSourceUrl]; Task { await model.batchExploreEnabled(!source.enabledExplore) }
        }
        Button("导出与二维码") { export(selected: [source.bookSourceUrl]) }
        if let entity = loginSource(source) {
            NavigationLink("调试") { SourceDebugView(source: entity, client: httpClient) }
            NavigationLink("登录") { SourceLoginDestination(source: entity, service: sourceLogin) }
            NavigationLink("校验") { CheckSourceView(sources: [entity], checker: sourceChecker) }
        }
        Button("删除", role: .destructive) { Task { await model.delete(source) } }
    }

    @ViewBuilder private var selectionActions: some View {
        Button("启用所选") { Task { await model.batchEnabled(true) } }
        Button("停用所选") { Task { await model.batchEnabled(false) } }
        Button("启用所选发现") { Task { await model.batchExploreEnabled(true) } }
        Button("停用所选发现") { Task { await model.batchExploreEnabled(false) } }
        Button("置顶所选") { Task { await model.move(selected: model.selectedURLs, toTop: true) } }
        Button("置底所选") { Task { await model.move(selected: model.selectedURLs, toTop: false) } }
        Button("添加分组") { removingGroup = false; groupText = ""; showGroup = true }
        Button("移除分组") { removingGroup = true; groupText = ""; showGroup = true }
        Button("导出所选") { export(selected: model.selectedURLs) }
    }

    private func edit(_ row: BookSourceRow) {
        do { editor = SourceEditorRequest(source: try JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode(row))) }
        catch { model.userError = error.presentation(operation: "打开书源编辑", subject: row.bookSourceName + " · " + row.bookSourceUrl) }
    }

    private func export(selected: Set<String>?) {
        do { shareText = try model.exportText(selected: selected); showShare = true }
        catch { model.userError = error.presentation(operation: "导出书源", subject: "所选书源") }
    }

    private func loginSource(_ row: BookSourceRow) -> BookSource? {
        try? JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode(row))
    }
}

private struct SourceEditorRequest: Identifiable { let id = UUID(); let source: BookSource? }
