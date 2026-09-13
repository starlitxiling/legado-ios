import SwiftUI
import LegadoCore

struct SourcesView: View {
    @State private var model: SourcesViewModel
    @State private var importEntry: ManagementImportEntry?
    private let replaceRules: ReplaceRuleRepository
    private let httpClient: any ResponseLimitedHttpClient
    private let sourceLogin: SourceLogin
    private let sourceChecker: SourceChecker

    init(repository: BookSourceRepository, replaceRules: ReplaceRuleRepository,
         httpClient: any ResponseLimitedHttpClient, sourceLogin: SourceLogin, sourceChecker: SourceChecker) {
        _model = State(initialValue: SourcesViewModel(repository: repository, httpClient: httpClient))
        self.replaceRules = replaceRules
        self.httpClient = httpClient
        self.sourceLogin = sourceLogin
        self.sourceChecker = sourceChecker
    }

    var body: some View {
        @Bindable var model = model
        List {
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
                        Text(source.bookSourceUrl).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if let group = source.bookSourceGroup, !group.isEmpty {
                            Text(group).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(model.isBusy)
                .contextMenu {
                    if let entity = loginSource(source) {
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
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("分组", selection: $model.selectedGroup) {
                        Text("全部").tag(nil as String?)
                        ForEach(model.groups, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                } label: { Label(model.selectedGroup ?? "分组", systemImage: "line.3.horizontal.decrease.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("从 URL 导入") { importEntry = .url }
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
    }

    private func loginSource(_ row: BookSourceRow) -> BookSource? {
        try? JSONDecoder().decode(BookSource.self, from: JSONEncoder().encode(row))
    }
}
