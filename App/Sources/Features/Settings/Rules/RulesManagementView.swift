import SwiftUI
import LegadoCore

struct TxtTocRulesView: View {
    let database: AppDatabase
    var body: some View { RulesManagementView(kind: .txt, database: database) }
}

struct DictRulesView: View {
    let database: AppDatabase
    var body: some View { RulesManagementView(kind: .dictionary, database: database) }
}

struct RulesManagementView: View {
    @State private var model: RulesManagementModel
    @State private var showEditor = false
    @State private var showImport = false

    init(kind: RulesManagementModel.Kind, database: AppDatabase) {
        _model = State(initialValue: RulesManagementModel(kind: kind, database: database))
    }

    var body: some View {
        @Bindable var model = model
        List {
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            if model.kind == .txt {
                ForEach(model.txtRules) { rule in
                    Toggle(rule.name, isOn: Binding(get: { rule.enable }, set: { value in
                        Task { await model.setEnabled(rule, enabled: value) }
                    }))
                    .contextMenu { Button("编辑") { model.edit(rule); showEditor = true } }
                    .swipeActions { Button("删除", role: .destructive) { Task { await model.delete(rule) } } }
                }
            } else {
                ForEach(model.dictRules) { rule in
                    Toggle(rule.name, isOn: Binding(get: { rule.enabled }, set: { value in
                        Task { await model.setEnabled(rule, enabled: value) }
                    }))
                    .contextMenu { Button("编辑") { model.edit(rule); showEditor = true } }
                    .swipeActions { Button("删除", role: .destructive) { Task { await model.delete(rule) } } }
                }
            }
        }
        .navigationTitle(model.kind == .txt ? "TXT 目录规则" : "字典规则")
        .toolbar {
            Button("新建", systemImage: "plus") {
                model.newRule(now: Int64(Date().timeIntervalSince1970 * 1000)); showEditor = true
            }
            Button("导入 JSON") { model.jsonText = ""; model.errorMessage = nil; showImport = true }
        }
        .disabled(model.isBusy)
        .task { await model.load() }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                Form {
                    if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                    if model.kind == .txt {
                        TextField("名称", text: $model.txtDraft.name)
                        TextField("正则表达式", text: $model.txtDraft.rule, axis: .vertical)
                        TextField("替换", text: $model.txtDraft.replacement)
                        TextField("示例", text: Binding(get: { model.txtDraft.example ?? "" }, set: { model.txtDraft.example = $0 }))
                        TextField("排序", value: $model.txtDraft.serialNumber, format: .number)
                        Toggle("启用", isOn: $model.txtDraft.enable)
                    } else {
                        TextField("名称", text: $model.dictDraft.name)
                        TextField("URL 规则", text: $model.dictDraft.urlRule, axis: .vertical)
                        TextField("显示规则", text: $model.dictDraft.showRule, axis: .vertical)
                        TextField("排序", value: $model.dictDraft.sortNumber, format: .number)
                        Toggle("启用", isOn: $model.dictDraft.enabled)
                    }
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .navigationTitle("编辑规则")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showEditor = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { Task { if await model.saveDraft() { showEditor = false } } }
                    }
                }.disabled(model.isBusy)
            }
        }
        .sheet(isPresented: $showImport) {
            NavigationStack {
                Form {
                    TextEditor(text: $model.jsonText).font(.system(.caption, design: .monospaced)).frame(minHeight: 300)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                }
                .navigationTitle("粘贴 JSON")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showImport = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入") {
                            Task { if await model.importJSON(now: Int64(Date().timeIntervalSince1970 * 1000)) { showImport = false } }
                        }
                    }
                }.disabled(model.isBusy)
            }
        }
    }
}
