import SwiftUI
import LegadoCore

struct BookInfoEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: BookInfoEditModel

    init(book: BookRow, repository: BookshelfRepository) {
        _model = State(initialValue: BookInfoEditModel(book: book, repository: repository))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            TextField("书名", text: $model.name)
            TextField("作者", text: $model.author)
            Section("自定义封面与简介（留空使用书源信息）") {
                TextField("封面 URL", text: $model.cover).textInputAutocapitalization(.never)
                TextEditor(text: $model.intro).frame(minHeight: 120)
            }
            TextField("自定义标签", text: $model.tag)
            Section("自定义字段（JSON 字符串键值）") {
                TextEditor(text: $model.variable).frame(minHeight: 100).textInputAutocapitalization(.never)
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            Button("保存") { Task { if await model.save() { dismiss() } } }
                .disabled(model.isSaving)
        }
        .navigationTitle("编辑书籍信息")
    }
}
