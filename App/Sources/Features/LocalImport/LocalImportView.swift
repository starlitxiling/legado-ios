import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LegadoCore

struct LocalImportView: View {
    @State private var model: LocalImportViewModel
    @State private var showsPicker = false
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
        _model = State(initialValue: LocalImportViewModel(database: database))
    }

    var body: some View {
        List {
            Section {
                Button("选择 TXT、EPUB、MOBI 或 PDF 文件") { showsPicker = true }.disabled(model.isImporting)
                ForEach(model.conflictingURLs, id: \.self) { url in
                    Button("确认保留副本：\(url.lastPathComponent)") {
                        Task { await model.confirmKeepCopy(url) }
                    }.disabled(model.isImporting)
                }
                if model.isImporting { ProgressView("正在导入") }
                if model.importedCount > 0 { Text("已导入 \(model.importedCount) 本书") }
                ForEach(Array(model.errors.enumerated()), id: \.offset) { _, error in
                    Text(error).foregroundStyle(.red)
                }
            } footer: { Text("文件会复制到应用内，之后无需保留原始文件。") }
            Section {
                NavigationLink("TXT 目录规则") { TxtTocRulesView(database: database) }
            }
        }
        .navigationTitle("导入本地书")
        .sheet(isPresented: $showsPicker) {
            LocalDocumentPicker { urls in
                showsPicker = false
                Task { await model.importFiles(urls) }
            }
        }
    }
}

private struct LocalDocumentPicker: UIViewControllerRepresentable {
    let selected: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.plainText, .pdf] + ["epub", "mobi", "azw3"].map { UTType(filenameExtension: $0) ?? .data }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: ([URL]) -> Void
        init(selected: @escaping ([URL]) -> Void) { self.selected = selected }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { selected(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { selected([]) }
    }
}
