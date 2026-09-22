import SwiftUI
import UniformTypeIdentifiers
import LegadoCore

struct BookshelfBookListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: BookshelfBookListModel
    @State private var task: Task<Void, Never>?
    @State private var choosingFile = false
    @State private var userError: UserFacingError?
    private var fileError: String? { userError?.displayText }
    let groupID: Int64

    init(database: AppDatabase, client: any HttpClient, groupID: Int64) {
        _model = State(initialValue: BookshelfBookListModel(database: database, client: client,
            concurrency: UserDefaults.standard.object(forKey: "threadCount") as? Int ?? 32))
        self.groupID = groupID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("粘贴书单 JSON 或网址") {
                    TextEditor(text: $model.input).frame(minHeight: 160)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.isImporting)
                        .accessibilityIdentifier("bookshelf.booklist.input")
                    Button("选择书单文件") { choosingFile = true }.disabled(model.isImporting)
                }
                Text("按书名和作者从已启用书源查找，已在书架的书籍将跳过。")
                if model.isImporting { ProgressView(value: Double(model.completed), total: Double(max(1, model.total))) }
                if model.total > 0 { Text("已处理 \(model.completed) / \(model.total)，失败 \(model.failures.count)") }
                if let fileError { Text(fileError).foregroundStyle(.red) }
                ForEach(Array(model.failures.enumerated()), id: \.offset) { _, error in Text(error).foregroundStyle(.red) }
            }
            .legadoNavigationTitle("导入书单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { task?.cancel(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { task = Task { await model.importBooks(groupID: groupID) } }
                        .disabled(model.isImporting || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.json, .plainText]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: BookshelfBookList.maximumBytes + 1) ?? Data()
                    _ = try BookshelfBookList.decode(data)
                    model.input = String(decoding: data, as: UTF8.self); userError = nil
                } catch { userError = error.presentation(operation: "读取书单文件", subject: (try? result.get())?.lastPathComponent) }
            }
        }.onDisappear { task?.cancel() }
    }
}
