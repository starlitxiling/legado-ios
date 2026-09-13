import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum ManagementImportEntry: String, Identifiable {
    case url, file, clipboard
    var id: String { rawValue }
}

struct SourceImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let entry: ManagementImportEntry
    let preview: ManagementImportPreview?
    let isBusy: Bool
    let errorMessage: String?
    let prepareText: (String) async -> Void
    let prepareURL: (String) async -> Void
    let confirm: () async -> Bool
    let cancel: () -> Void
    var keepEnable: Binding<Bool>? = nil
    @State private var address = ""
    @State private var text = ""
    @State private var showsFilePicker = false
    @State private var fileError: String?

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    Section("导入预览") {
                        LabeledContent("新增", value: "\(preview.newCount) 条")
                        LabeledContent("覆盖现有", value: "\(preview.overwriteCount) 条")
                        if let keepEnable {
                            Toggle("保留本地启用状态", isOn: keepEnable)
                        }
                        if title == "书源" {
                            LabeledContent("JS 书源", value: "\(preview.jsSourceCount) 条")
                            Text("相同地址仅保留最后一条。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("确认导入") {
                            Task { if await confirm() { dismiss() } }
                        }
                        .disabled(isBusy || preview.importableCount == 0)
                        Button("重新选择内容") { cancel() }
                            .disabled(isBusy)
                    }
                } else {
                    Section("从 URL 下载") {
                        TextField("https://example.com/sources.json", text: $address)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("下载并预览") {
                            fileError = nil
                            Task { await prepareURL(address) }
                        }
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Section("JSON 文本") {
                        TextEditor(text: $text).frame(minHeight: 160)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("待导入的 JSON 文本")
                        Button("从剪贴板粘贴") { text = UIPasteboard.general.string ?? "" }
                        Button("预览文本") {
                            fileError = nil
                            Task { await prepareText(text) }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Section {
                        Button("选择 JSON 文件") { showsFilePicker = true }
                        Text("支持 UTF-8 JSON，最大 16 MB。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if isBusy { ProgressView("正在处理") }
                if let error = fileError ?? errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .disabled(isBusy)
            .navigationTitle("导入\(title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancel(); dismiss() }.disabled(isBusy)
                }
            }
            .sheet(isPresented: $showsFilePicker) {
                ManagementDocumentPicker { result in
                    switch result {
                    case .success(let value):
                        fileError = nil
                        text = value
                        Task { await prepareText(value) }
                    case .failure(let error): fileError = error.localizedDescription
                    }
                }
            }
            .task {
                switch entry {
                case .url: break
                case .file: showsFilePicker = true
                case .clipboard: text = UIPasteboard.general.string ?? ""
                }
            }
        }
        .interactiveDismissDisabled(isBusy)
    }
}

private struct ManagementDocumentPicker: UIViewControllerRepresentable {
    let completion: (Result<String, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .plainText], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Result<String, Error>) -> Void
        init(completion: @escaping (Result<String, Error>) -> Void) { self.completion = completion }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            completion(Result {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: ManagementImport.maximumBytes + 1) ?? Data()
                return try ManagementImport.text(data)
            })
        }
    }
}
