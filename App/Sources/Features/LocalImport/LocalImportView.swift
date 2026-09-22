import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LegadoCore

struct LocalImportView: View {
    @State private var model: LocalImportViewModel
    @State private var showsPicker = false
    @State private var showsDirectoryPicker = false
    @State private var scanner = LocalDirectoryScanner()
    @State private var onlineURL = ""
    @State private var userError: UserFacingError?
    private var pickerError: String? { userError?.displayText }
    @State private var importedInitialURLs = false
    private let initialURLs: [URL]
    private let database: AppDatabase

    init(database: AppDatabase, initialURLs: [URL] = []) {
        self.database = database
        self.initialURLs = initialURLs
        _model = State(initialValue: LocalImportViewModel(database: database))
    }

    var body: some View {
        List {
            Section {
                Button("选择书籍或 ZIP / RAR / 7z 压缩包") { showsPicker = true }.disabled(model.isImporting || model.isDownloading)
                ForEach(model.conflictingURLs, id: \.self) { url in
                    Button("确认保留副本：\(url.lastPathComponent)") {
                        Task { await model.confirmKeepCopy(url) }
                    }.disabled(model.isImporting || model.isDownloading)
                }
                if model.isImporting { ProgressView("正在导入") }
                if model.importedCount > 0 { Text("已导入 \(model.importedCount) 本书") }
                ForEach(Array(model.errors.enumerated()), id: \.offset) { _, error in
                    Text(error).foregroundStyle(.red)
                }
            } footer: { Text("文件会复制到应用内，之后无需保留原始文件。") }
            Section("扫描目录") {
                Button("添加扫描目录") { showsDirectoryPicker = true }.disabled(scanner.isScanning)
                ForEach(scanner.directories) { directory in
                    HStack {
                        Button(directory.name) { Task { await scanner.scan(directory.id) } }.disabled(scanner.isScanning)
                        Spacer()
                        Button(role: .destructive) { scanner.remove(directory.id) } label: { Image(systemName: "trash") }
                            .accessibilityLabel("移除目录")
                    }
                }
                if scanner.isScanning { ProgressView("正在扫描") }
                if let error = scanner.errorMessage { Text(error).foregroundStyle(.red) }
                if let pickerError { Text(pickerError).foregroundStyle(.red) }
                if !scanner.files.isEmpty {
                    Button("导入扫描结果（\(scanner.files.count) 个文件）") { Task { await scanner.importScanned(using: model) } }
                        .disabled(model.isImporting || model.isDownloading)
                    ForEach(scanner.files.prefix(30), id: \.self) { Text($0.lastPathComponent).font(.footnote) }
                }
            }
            Section("在线文件") {
                TextField("书籍或压缩包下载网址", text: $onlineURL).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().keyboardType(.URL)
                Button("下载并导入") { Task { await model.importOnline(onlineURL) } }
                    .disabled(onlineURL.isEmpty || model.isDownloading || model.isImporting)
                if model.isDownloading { ProgressView("正在下载") }
            }
            Section {
                NavigationLink("TXT 目录规则") { TxtTocRulesView(database: database) }
            }
        }
        .legadoNavigationTitle("导入本地书")
        .task {
            guard !importedInitialURLs else { return }
            importedInitialURLs = true
            if !initialURLs.isEmpty { await model.importFiles(initialURLs) }
        }
        .fileImporter(isPresented: $showsDirectoryPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await scanner.add(url) }
            case .failure(let error): userError = error.presentation(operation: "选择扫描目录", subject: nil)
            }
        }
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
        let types: [UTType] = [.plainText, .pdf] + ["epub", "umd", "mobi", "azw3", "azw", "zip", "rar", "7z"].map { UTType(filenameExtension: $0) ?? .data }
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
