import SwiftUI
import LegadoCore

struct AddBookURLView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: AddBookURLModel
    @State private var task: Task<Void, Never>?
    let groupID: Int64

    init(database: AppDatabase, client: any HttpClient, groupID: Int64) {
        _model = State(initialValue: AddBookURLModel(database: database, client: client))
        self.groupID = groupID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("书籍网址，每行一个") {
                    TextEditor(text: $model.input).frame(minHeight: 140)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(model.isAdding)
                }
                if model.isAdding { ProgressView("添加中") }
                if model.completed > 0 { Text("已添加 \(model.completed) 本") }
                ForEach(Array(model.failures.enumerated()), id: \.offset) { _, message in Text(message) }
            }
            .legadoNavigationTitle("添加网址")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { task?.cancel(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { task = Task { await model.add(groupID: groupID) } }
                        .disabled(model.isAdding || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onDisappear { task?.cancel() }
    }
}
