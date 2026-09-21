import SwiftUI
import LegadoCore

struct ReaderManualReplaceView: View {
    let model: ReaderViewModel
    let repository: ReplaceRuleRepository
    @State private var rules: [ReplaceRuleRow] = []
    @State private var selected: Set<Int64?> = []
    @State private var enabled = false
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("手动替换", isOn: $enabled)
                } footer: {
                    Text("启用后仅使用本书勾选的规则，忽略规则的全局启用状态和适用范围。不勾选规则则不执行替换。")
                }
                Section {
                    ForEach(rules, id: \.id) { rule in
                        Toggle(isOn: Binding(get: { selected.contains(rule.id) }, set: { value in
                            if value { selected.insert(rule.id) } else { selected.remove(rule.id) }
                        })) {
                            VStack(alignment: .leading) {
                                Text(rule.name.isEmpty ? rule.pattern : rule.name)
                                Text(rule.pattern).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }.disabled(saving).legadoNavigationTitle("手动替换")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(saving) }
                    ToolbarItem(placement: .bottomBar) {
                        Button(selected.count == rules.count ? "取消全选" : "全选") {
                            selected = selected.count == rules.count ? [] : Set(rules.map(\.id))
                        }
                    }
                }
                .task {
                    do {
                        rules = try await repository.list().filter { !($0.scopeSource && !$0.scopeTitle && !$0.scopeContent) }
                        selected = Set(model.readerBook?.readConfig?.manualReplaceRuleIds ?? []).intersection(rules.map(\.id))
                        enabled = UserDefaults.standard.bool(forKey: "manualReplaceRule")
                    } catch { self.error = error.localizedDescription }
                }
        }.interactiveDismissDisabled(saving)
            .alert("手动替换", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好") { error = nil }
            } message: { Text(error ?? "") }
    }

    private func save() {
        let ids = rules.filter { selected.contains($0.id) }.map(\.id)
        let enabled = enabled
        saving = true
        Task {
            let previous = UserDefaults.standard.bool(forKey: "manualReplaceRule")
            UserDefaults.standard.set(enabled, forKey: "manualReplaceRule")
            await model.updateReadConfig { $0.manualReplaceRuleIds = ids }
            saving = false
            if let message = model.errorMessage {
                UserDefaults.standard.set(previous, forKey: "manualReplaceRule")
                error = message
            } else { dismiss() }
        }
    }
}
