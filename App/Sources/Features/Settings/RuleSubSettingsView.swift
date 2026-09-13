import SwiftUI
import LegadoCore

struct RuleSubSettingsView: View {
    @State private var model: SubscriptionSettingsModel
    @State private var editing: RuleSub?
    @State private var showEditor = false
    @State private var importText = ""

    init(database: AppDatabase, client: any HttpClient) {
        _model = State(initialValue: SubscriptionSettingsModel(database: database, client: client))
    }

    var body: some View {
        List {
            Section("导入订阅配置") {
                TextField("JSON 或配置文件 URL", text: $importText, axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("导入") { Task { await model.importText(importText) } }
            }
            Section("订阅规则") {
                ForEach(model.subscriptions, id: \.id) { subscription in
                    VStack(alignment: .leading) {
                        Button(subscription.name) { editing = subscription; showEditor = true }
                        Text(subscription.url).font(.caption).foregroundStyle(.secondary)
                        Button("更新规则") { Task { await model.refresh(subscription) } }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { Task { await model.delete(subscription) } }
                    }
                }
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            if let message = model.message { Text(message) }
        }
        .disabled(model.isBusy)
        .navigationTitle("规则订阅")
        .toolbar { Button("添加") { editing = nil; showEditor = true } }
        .task { await model.load() }
        .sheet(isPresented: $showEditor) { RuleSubEditor(value: editing ?? RuleSub(), model: model) }
    }
}

private struct RuleSubEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var value: RuleSub
    let model: SubscriptionSettingsModel

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $value.name)
                TextField("订阅 URL", text: $value.url).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("类型", selection: $value.type) {
                    Text("书源").tag(0); Text("订阅源").tag(1); Text("替换规则").tag(2)
                }
                TextField("排序", value: $value.customOrder, format: .number)
                Toggle("自动更新", isOn: $value.autoUpdate)
                TextField("更新间隔", value: $value.updateInterval, format: .number)
                Toggle("静默更新", isOn: $value.silentUpdate)
                Text("自动更新选项用于保存订阅配置；当前可通过列表按钮手动更新。").font(.caption)
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("编辑订阅")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { if await model.save(value) { dismiss() } } }
                }
            }
        }
    }
}
