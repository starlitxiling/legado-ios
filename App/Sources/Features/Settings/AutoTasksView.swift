import SwiftUI
import LegadoCore

struct AutoTasksView: View {
    let container: AppContainer
    @State private var rules: [AutoTaskRule] = []
    private struct EditRequest: Identifiable { let id = UUID(); let rule: AutoTaskRule }
    @State private var editing: EditRequest?
    @State private var error: String?
    var body: some View {
        List {
            Text("使用五段 Cron 表达式。前台每分钟检查；后台运行时间由 iOS 决定。").font(.footnote).foregroundStyle(.secondary)
            ForEach(rules, id: \.id) { rule in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(rule.name, isOn: Binding(get: { rule.enable }, set: { enabled in
                        var updated = rule; updated.enable = enabled; Task { await save(updated) }
                    }))
                    Text(rule.cron ?? "").font(.caption.monospaced())
                    if let log = rule.lastLog { Text(log).font(.caption).lineLimit(4).textSelection(.enabled) }
                    HStack {
                        Button("编辑") { editing = EditRequest(rule: rule) }
                        Button("立即运行") { Task { await container.autoTasks.run(rule); await load() } }
                    }.buttonStyle(.borderless)
                }.swipeActions { Button("删除", role: .destructive) { Task {
                    do { try await AutoTaskRuleRepository(database: container.database).delete(rule); await load() }
                    catch { self.error = error.localizedDescription }
                } } }
            }
            if let error = error ?? container.autoTasks.errorMessage { Text(error).foregroundStyle(.red) }
        }.legadoNavigationTitle("定时任务")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("新建") { editing = EditRequest(rule: AutoTaskRule()) } } }
            .sheet(item: $editing) { request in
                AutoTaskEditor(rule: request.rule) { rule in
                    try await AutoTaskRuleRepository(database: container.database).upsert(rule)
                    await load()
                }
            }
            .task { await load() }
            .disabled(container.autoTasks.isRunning)
    }
    private func load() async {
        do { rules = try await AutoTaskRuleRepository(database: container.database).all().sorted { $0.customOrder < $1.customOrder } }
        catch { self.error = error.localizedDescription }
    }
    private func save(_ rule: AutoTaskRule) async {
        do { try await AutoTaskRuleRepository(database: container.database).upsert(rule); await load() }
        catch { self.error = error.localizedDescription }
    }
}

private struct AutoTaskEditor: View {
    @State var rule: AutoTaskRule
    let save: (AutoTaskRule) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $rule.name)
                TextField("Cron", text: Binding(get: { rule.cron ?? "" }, set: { rule.cron = $0 })).textInputAutocapitalization(.never)
                Toggle("启用", isOn: $rule.enable)
                TextField("备注", text: Binding(get: { rule.comment ?? "" }, set: { rule.comment = $0 }), axis: .vertical)
                Text("脚本").font(.caption)
                TextEditor(text: $rule.script).font(.system(.body, design: .monospaced)).frame(minHeight: 220).autocorrectionDisabled().textInputAutocapitalization(.never)
                if let error { Text(error).foregroundStyle(.red) }
            }.legadoNavigationTitle("编辑定时任务")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") {
                        do {
                            _ = try CronSchedule(rule.cron ?? "")
                            guard !rule.name.isEmpty, !rule.script.isEmpty else { throw JsEngineError.exception("名称和脚本不能为空") }
                            Task {
                                do { try await save(rule); dismiss() }
                                catch { self.error = error.localizedDescription }
                            }
                        } catch { self.error = error.localizedDescription }
                    } }
                }
        }
    }
}
