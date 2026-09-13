import SwiftUI
import LegadoCore

struct ReplaceRuleEditView: View {
    @State private var model: ReplaceRuleEditModel
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    let repository: ReplaceRuleRepository
    let onSave: () async -> Void

    init(rule: ReplaceRuleRow?, repository: ReplaceRuleRepository, onSave: @escaping () async -> Void) {
        _model = State(initialValue: ReplaceRuleEditModel(rule: rule ?? ReplaceRuleRow()))
        self.repository = repository; self.onSave = onSave
    }

    var body: some View {
        @Bindable var model = model
        Form {
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            Section("规则") {
                TextField("名称", text: $model.rule.name)
                TextField("分组", text: optional(\.group))
                TextField("匹配", text: $model.rule.pattern, axis: .vertical)
                TextField("替换为", text: $model.rule.replacement, axis: .vertical)
                Toggle("启用", isOn: $model.rule.isEnabled)
                Toggle("正则表达式", isOn: $model.rule.isRegex)
            }
            Section("适用范围") {
                TextField("范围", text: optional(\.scope))
                TextField("排除范围", text: optional(\.excludeScope))
                Toggle("标题", isOn: $model.rule.scopeTitle)
                Toggle("正文", isOn: $model.rule.scopeContent)
                Toggle("书源", isOn: $model.rule.scopeSource)
                LabeledContent("超时（毫秒）") { TextField("3000", value: $model.rule.timeoutMillisecond, format: .number) }
                LabeledContent("排序") { TextField("排序", value: $model.rule.order, format: .number) }
            }
            Section("JSON 粘贴") {
                TextEditor(text: $model.jsonText).font(.system(.caption, design: .monospaced)).frame(minHeight: 130)
                Button("应用 JSON") {
                    do { try model.applyJSON(); model.errorMessage = nil }
                    catch { model.errorMessage = error.localizedDescription }
                }
            }
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .navigationTitle("替换规则编辑")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task {
                        saving = true
                        defer { saving = false }
                        do { try await model.save(repository: repository); await onSave(); dismiss() }
                        catch { model.errorMessage = error.localizedDescription }
                    }
                }
            }
        }.disabled(saving)
    }

    private func optional(_ key: WritableKeyPath<ReplaceRuleRow, String?>) -> Binding<String> {
        Binding(get: { model.rule[keyPath: key] ?? "" }, set: { model.rule[keyPath: key] = $0.isEmpty ? nil : $0 })
    }
}
