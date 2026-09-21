import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LegadoCore

struct BackupView: View {
    let container: AppContainer
    @Bindable var settings: SettingsViewModel
    @Binding var model: BackupViewModel?
    @State private var setupError: String?
    @State private var selectingFile = false
    @State private var selectedBackup: WebDavFile?

    var body: some View {
        List {
            Section("WebDAV 设置") {
                TextField("服务器地址", text: $settings.address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("账号", text: $settings.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("密码", text: $settings.password)
                let controls = PreferenceControls(preferences: model?.preferences ?? AppPreferences.shared)
                controls.text("子文件夹", "webDavDir")
                controls.text("设备名称", "webDavDeviceName")
                controls.toggle("恢复缺失本地书", "webDavBookAutoRestore")
                controls.toggle("同步阅读进度", "syncBookProgress")
                controls.toggle("同步增强", "syncBookProgressPlus")
                Button("保存账号") { settings.save() }
                Button("测试连接") { Task { await settings.testConnection() } }.disabled(settings.isTesting)
                Button("删除账号", role: .destructive) { settings.clearCredentials() }
                if let message = settings.message { Text(message).foregroundStyle(.secondary) }
                if let error = settings.errorMessage { Text(error).foregroundStyle(.red) }
            }

            if let model {
                Section("备份与恢复") {
                    BackupConfigurationFields(preferences: model.preferences)
                    Button("备份到 WebDAV") {
                        Task {
                            do {
                                try model.configure(credentials: settings.credentials(), httpClient: container.httpClient)
                                await model.createBackup(upload: true)
                            } catch { model.errorMessage = error.localizedDescription }
                        }
                    }
                    Button("生成本地备份") { Task { await model.createBackup(upload: false) } }
                    if let file = model.exportedFile { ShareLink("保存或分享 ZIP", item: file) }
                    Button("立即同步阅读进度") {
                        Task {
                            do {
                                try model.configure(credentials: settings.credentials(), httpClient: container.httpClient)
                                await model.synchronizeProgress()
                            } catch { model.errorMessage = error.localizedDescription }
                        }
                    }
                    if let message = model.statusMessage { Text(message).foregroundStyle(.secondary) }
                    Button("列出 WebDAV 备份") {
                        Task {
                            do {
                                try model.configure(credentials: settings.credentials(), httpClient: container.httpClient)
                                await model.listBackups()
                            } catch { model.errorMessage = error.localizedDescription }
                        }
                    }
                    Button("从本地 ZIP 恢复") { selectingFile = true }
                    Text("恢复会合并备份数据，相同记录可能被覆盖。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .disabled(model.isBusy)
                if model.isBusy { ProgressView("正在处理，请勿重复导入") }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                Section("远端备份") {
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
        .legadoNavigationTitle("备份与恢复")
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
