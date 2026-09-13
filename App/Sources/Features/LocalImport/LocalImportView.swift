import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LegadoCore

struct LocalImportView: View {
    @State private var model: LocalImportViewModel
    @State private var showsPicker = false

    init(database: AppDatabase) { _model = State(initialValue: LocalImportViewModel(database: database)) }

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
                NavigationLink("TXT 目录规则") { TxtTocRulesView(model: model) }
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

private struct TxtTocRulesView: View {
    @Bindable var model: LocalImportViewModel
    var body: some View {
        List {
            if let error = model.ruleError { Text(error).foregroundStyle(.red) }
            Section {
                ForEach(model.rules) { rule in
                    NavigationLink {
                        TxtTocRuleEditor(model: model, rule: rule)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(rule.name)
                            Text(rule.enable ? "已启用" : "已停用").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: { Text("规则修改用于后续导入的 TXT 书籍。") }
        }
        .navigationTitle("TXT 目录规则")
        .task { await model.loadRules() }
    }
}

private struct TxtTocRuleEditor: View {
    @Bindable var model: LocalImportViewModel
    @State var rule: TxtTocRule
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("名称", text: $rule.name)
            Toggle("启用", isOn: $rule.enable)
            Section("正则表达式") { TextEditor(text: $rule.rule).frame(minHeight: 140).autocorrectionDisabled() }
            if let example = rule.example { Section("示例") { Text(example) } }
            if let error = model.ruleError { Text(error).foregroundStyle(.red) }
            Button("保存") {
                Task { await model.saveRule(rule); if model.ruleError == nil { dismiss() } }
            }
        }
        .navigationTitle("编辑目录规则")
    }
}
