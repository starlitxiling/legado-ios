import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LegadoCore

struct BackupView: View {
    let container: AppContainer
    let settings: SettingsViewModel
    @Binding var model: BackupViewModel?
    @State private var setupError: String?
    @State private var selectingFile = false
    @State private var selectedBackup: WebDavFile?

    var body: some View {
        List {
            if let model {
                Section {
                    Button("列出 WebDAV 备份") {
                        Task {
                            do {
                                try model.configure(credentials: settings.credentials(), httpClient: container.httpClient)
                                await model.listBackups()
                            } catch { model.errorMessage = error.localizedDescription }
                        }
                    }
                    Button("从本地 ZIP 恢复") { selectingFile = true }
                    Text("恢复会合并备份数据，相同记录可能被覆盖。WebDAV 仅使用读取操作。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .disabled(model.isBusy)
                if model.isBusy { ProgressView("正在处理，请勿重复导入") }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                Section("legado 目录备份") {
                    ForEach(model.files, id: \.url) { file in
                        Button(file.displayName) { selectedBackup = file }
                            .disabled(model.isBusy)
                    }
                    if model.files.isEmpty { Text("尚无备份，请先列出远端目录。") }
                }
                if let report = model.report { RestoreResultView(report: report) }
            } else if let setupError {
                Text(setupError).foregroundStyle(.red)
                Button("重试") { prepare() }
            } else { ProgressView() }
        }
        .navigationTitle("备份与恢复")
        .task { if model == nil { prepare() } }
        .confirmationDialog("恢复这份备份？相同记录可能被覆盖。", isPresented: Binding(
            get: { selectedBackup != nil }, set: { if !$0 { selectedBackup = nil } }
        ), titleVisibility: .visible) {
            if let file = selectedBackup {
                Button("恢复 \(file.displayName)", role: .destructive) {
                    Task { await model?.restore(file) }
                    selectedBackup = nil
                }
            }
        }
        .sheet(isPresented: $selectingFile) {
            BackupDocumentPicker { url in
                selectingFile = false
                if let url { Task { await model?.restoreLocalFile(url) } }
            }
        }
    }

    private func prepare() {
        do {
            let deviceID = try SettingsViewModel.localDeviceID(store: KeychainStore())
            model = BackupViewModel(database: container.database, localDeviceID: deviceID)
            setupError = nil
        } catch { setupError = error.localizedDescription }
    }
}

private struct BackupDocumentPicker: UIViewControllerRepresentable {
    let selected: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: (URL?) -> Void
        init(selected: @escaping (URL?) -> Void) { self.selected = selected }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            selected(urls.first)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { selected(nil) }
    }
}
