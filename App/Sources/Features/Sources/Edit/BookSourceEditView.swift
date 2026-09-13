import SwiftUI
import LegadoCore

struct BookSourceEditView: View {
    @State private var model: BookSourceEditModel
    @State private var jsonMode = false
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    private let repository: BookSourceRepository
    private let client: any HttpClient
    private let login: SourceLogin
    private let checker: SourceChecker
    private let onSave: () async -> Void

    init(source: BookSource?, repository: BookSourceRepository, client: any HttpClient,
         login: SourceLogin, checker: SourceChecker, onSave: @escaping () async -> Void) {
        _model = State(initialValue: BookSourceEditModel(source: source ?? BookSource(), isNew: source == nil))
        self.repository = repository; self.client = client; self.login = login
        self.checker = checker; self.onSave = onSave
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("JSON 模式", isOn: Binding(get: { jsonMode }, set: { enabled in
                do {
                    if !enabled { try model.applyJSON(model.jsonText) }
                    jsonMode = enabled; model.errorMessage = nil
                } catch { model.errorMessage = error.localizedDescription }
            }))
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            if jsonMode {
                TextEditor(text: $model.jsonText).font(.system(.caption, design: .monospaced)).frame(minHeight: 400)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("应用 JSON") { applyJSON() }
            } else {
                ForEach(BookSourceEditModel.groups) { group in
                    Section(group.title) {
                        ForEach(group.fields, id: \.self) { field in
                            VStack(alignment: .leading) {
                                Text(field).font(.caption).foregroundStyle(.secondary)
                                TextField(field, text: Binding(get: { model.value(field) }, set: {
                                    do { try model.setValue($0, for: field); model.errorMessage = nil }
                                    catch { model.errorMessage = error.localizedDescription }
                                }), axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                            }
                        }
                    }
                }
                Section("测试") {
                    NavigationLink("调试") { SourceDebugView(source: model.source, client: client) }
                    NavigationLink("登录") { SourceLoginDestination(source: model.source, service: login) }
                    NavigationLink("校验") { CheckSourceView(sources: [model.source], checker: checker) }
                }
            }
        }
        .navigationTitle("书源编辑")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving) }
        }
        .disabled(saving)
    }

    private func applyJSON() {
        do { try model.applyJSON(model.jsonText); model.errorMessage = nil }
        catch { model.errorMessage = error.localizedDescription }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await model.save(repository: repository, jsonMode: jsonMode, now: Int64(Date().timeIntervalSince1970 * 1000))
            await onSave(); dismiss()
        } catch { model.errorMessage = error.localizedDescription }
    }
}
