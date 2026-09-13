import SwiftUI
import LegadoCore

struct FormLoginView: View {
    @State private var model: SourceLoginViewModel
    init(source: BookSource, service: SourceLogin) {
        _model = State(initialValue: SourceLoginViewModel(source: source, service: service))
    }
    var body: some View {
        @Bindable var model = model
        Form {
            ForEach(model.rows) { row in
                let value = Binding(get: { model.values[row.name] ?? "" }, set: { model.values[row.name] = $0 })
                let title = row.viewName ?? row.name
                switch row.type {
                case "password": SecureField(title, text: value)
                case "button": Button(title) { Task { await model.submit(action: row.action) } }
                case "label": Text(title)
                case "toggle": Toggle(title, isOn: Binding(get: { value.wrappedValue == "true" }, set: { value.wrappedValue = String($0) }))
                case "select": Picker(title, selection: value) {
                    ForEach(row.options ?? [], id: \.self) { Text($0).tag($0) }
                }
                default: TextField(title, text: value).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            Button("登录") { Task { await model.submit() } }
                .disabled(model.rows.isEmpty)
            if model.completed { Text("登录脚本已执行").foregroundStyle(.green) }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .disabled(model.isBusy)
        .overlay { if model.isBusy { ProgressView() } }
        .navigationTitle("书源登录")
        .task { await model.load() }
    }
}
