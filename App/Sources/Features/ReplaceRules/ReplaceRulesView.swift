import SwiftUI
import LegadoCore

struct ReplaceRulesView: View {
    @State private var model: ReplaceRulesViewModel
    @State private var importEntry: ManagementImportEntry?
    @State private var editingRule: ReplaceRuleRow?
    @State private var showEditor = false
    @State private var shareText = ""
    @State private var showShare = false
    private let repository: ReplaceRuleRepository

    init(repository: ReplaceRuleRepository, httpClient: any ResponseLimitedHttpClient) {
        _model = State(initialValue: ReplaceRulesViewModel(repository: repository, httpClient: httpClient))
        self.repository = repository
    }

    var body: some View {
        @Bindable var model = model
        List {
            if let error = model.errorMessage, importEntry == nil {
                Text(error).foregroundStyle(.red)
                Button("重试") { Task { await model.load() } }
            }
            ForEach(model.filteredRules, id: \.id) { rule in
                Toggle(isOn: Binding(get: { rule.isEnabled }, set: { enabled in
                    Task { await model.setEnabled(rule, enabled: enabled) }
                })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.name.isEmpty ? "未命名规则" : rule.name)
                        Text(rule.pattern).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if let group = rule.group, !group.isEmpty {
                            Text(group).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(model.isBusy)
                .contextMenu { Button("编辑") { editingRule = rule; showEditor = true } }
                .swipeActions {
                    Button("删除", role: .destructive) { Task { await model.delete(rule) } }
                        .disabled(model.isBusy)
                }
            }
        }
        .overlay {
            if model.isBusy { ProgressView() }
            else if model.filteredRules.isEmpty && model.errorMessage == nil {
                ContentUnavailableView("没有替换规则", systemImage: "text.badge.checkmark",
                                       description: Text("导入规则，或调整搜索和分组条件。"))
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle("替换规则")
        .searchable(text: $model.keyword, prompt: "名称、匹配文本或分组")
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
                    Button("新建规则") { editingRule = nil; showEditor = true }
                    Button("导出 JSON") {
                        do { shareText = try ReplaceRuleEditModel.export(model.filteredRules); showShare = true }
                        catch { model.errorMessage = error.localizedDescription }
                    }
                    Button("从文件导入") { importEntry = .file }
                    Button("从剪贴板导入") { importEntry = .clipboard }
                } label: { Label("导入", systemImage: "square.and.arrow.down") }
                .disabled(model.isBusy)
            }
        }
        .sheet(item: $importEntry, onDismiss: { model.cancelImport() }) { entry in
            SourceImportSheet(title: "替换规则", entry: entry, preview: model.importPreview,
                              isBusy: model.isBusy, errorMessage: model.errorMessage,
                              prepareText: { await model.prepareImport(text: $0) },
                              prepareURL: { await model.prepareImport(url: $0) },
                              confirm: {
                                  await model.confirmImport()
                                  return model.importPreview == nil && model.errorMessage == nil
                              }, cancel: { model.cancelImport() })
        }
        .task { await model.load() }
        .sheet(isPresented: $showEditor) {
            NavigationStack { ReplaceRuleEditView(rule: editingRule, repository: repository, onSave: { await model.load() }) }
        }
        .sheet(isPresented: $showShare) { NavigationStack { SourceJSONShareView(text: shareText) } }
    }
}
