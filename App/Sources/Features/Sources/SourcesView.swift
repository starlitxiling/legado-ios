import SwiftUI
import LegadoCore

struct SourcesView: View {
    @State private var model: SourcesViewModel
    @State private var importEntry: ManagementImportEntry?
    @State private var editingSource: BookSource?
    @State private var showEditor = false
    @State private var shareText = ""
    @State private var showShare = false
    @State private var groupText = ""
    @State private var showGroup = false
    @State private var removingGroup = false
    private let repository: BookSourceRepository
    private let replaceRules: ReplaceRuleRepository
    private let httpClient: any ResponseLimitedHttpClient
    private let sourceLogin: SourceLogin
    private let sourceChecker: SourceChecker

    init(repository: BookSourceRepository, replaceRules: ReplaceRuleRepository,
         httpClient: any ResponseLimitedHttpClient, sourceLogin: SourceLogin, sourceChecker: SourceChecker) {
        _model = State(initialValue: SourcesViewModel(repository: repository, httpClient: httpClient))
        self.replaceRules = replaceRules
        self.repository = repository
        self.httpClient = httpClient
        self.sourceLogin = sourceLogin
        self.sourceChecker = sourceChecker
    }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedURLs) {
            if let error = model.errorMessage, importEntry == nil {
                Text(error).foregroundStyle(.red)
                Button("重试") { Task { await model.load() } }
            }
            ForEach(model.filteredSources, id: \.bookSourceUrl) { source in
                Toggle(isOn: Binding(get: { source.enabled }, set: { enabled in
                    Task { await model.setEnabled(source, enabled: enabled) }
                })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.bookSourceName.isEmpty ? "未命名书源" : source.bookSourceName)
                        if !(source.mainJs ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("JS 书源").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(source.bookSourceUrl).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if let group = source.bookSourceGroup, !group.isEmpty {
                            Text(group).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(model.isBusy)
                .tag(source.bookSourceUrl)
                .contextMenu {
                    Button("编辑") { editingSource = loginSource(source); showEditor = true }
                    Button("置顶") { Task { await model.move(selected: [source.bookSourceUrl], toTop: true) } }
                    Button("置底") { Task { await model.move(selected: [source.bookSourceUrl], toTop: false) } }
                    Button("导出与二维码") { export(selected: [source.bookSourceUrl]) }
                    if let entity = loginSource(source) {
                        NavigationLink("调试") { SourceDebugView(source: entity, client: httpClient) }
                        NavigationLink("登录") { SourceLoginDestination(source: entity, service: sourceLogin) }
                        NavigationLink("校验") { CheckSourceView(sources: [entity], checker: sourceChecker) }
                    }
                }
                .swipeActions {
                    Button("删除", role: .destructive) { Task { await model.delete(source) } }
                        .disabled(model.isBusy)
                }
            }
        }
        .overlay {
            if model.isBusy { ProgressView() }
            else if model.filteredSources.isEmpty && model.errorMessage == nil {
                ContentUnavailableView("没有书源", systemImage: "tray", description: Text("导入书源，或调整搜索和分组条件。"))
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle("书源")
        .searchable(text: $model.keyword, prompt: "名称、地址或分组")
        .refreshable { await model.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("分组", selection: $model.selectedGroup) {
                        Text("全部").tag(nil as String?)
                        ForEach(model.groups, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Picker("排序", selection: $model.sort) {
                        ForEach(SourceSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("默认方向", isOn: $model.ascending)
                } label: { Label(model.selectedGroup ?? "分组", systemImage: "line.3.horizontal.decrease.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("从 URL 导入") { importEntry = .url }
                    Button("新建书源") { editingSource = nil; showEditor = true }
                    Button("导出当前列表") { export(selected: nil) }
                    if !model.selectedURLs.isEmpty {
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
                              }, cancel: { model.cancelImport() }, keepEnable: $model.keepEnable)
        }
        .task { await model.load() }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                BookSourceEditView(source: editingSource, repository: repository, client: httpClient,
                    login: sourceLogin, checker: sourceChecker, onSave: { await model.load() })
            }
        }
        .sheet(isPresented: $showShare) { NavigationStack { SourceJSONShareView(text: shareText) } }
        .alert(removingGroup ? "移除分组" : "添加分组", isPresented: $showGroup) {
            TextField("分组名称，多个名称用逗号分隔", text: $groupText)
            Button("取消", role: .cancel) {}
            Button("确定") { Task { await model.changeGroup(groupText, removing: removingGroup) } }
        }
    }

    private func export(selected: Set<String>?) {
        do { shareText = try model.exportText(selected: selected); showShare = true }
        catch { model.errorMessage = error.localizedDescription }
    }

    private func loginSource(_ row: BookSourceRow) -> BookSource? {
        try? JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode(row))
    }
}
