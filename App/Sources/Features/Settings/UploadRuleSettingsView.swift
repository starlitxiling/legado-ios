import SwiftUI
import UniformTypeIdentifiers
import LegadoCore

struct UploadRuleSettingsView: View {
    @State private var model: UploadRuleSettingsModel
    @State private var importing = false
    init(database: AppDatabase) { _model = State(initialValue: UploadRuleSettingsModel(database: database)) }
    var body: some View {
        @Bindable var model = model
        Form {
            TextField("导入地址", text: $model.address).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("从 URL 导入") {
                Task {
                    do { model.text = try await ManagementImport.download(model.address, client: ImportHttpClient()) }
                    catch { model.message = error.localizedDescription }
                }
            }
            Button("从文件导入") { importing = true }
            TextEditor(text: $model.text).font(.system(.caption, design: .monospaced)).frame(minHeight: 240)
            Button("保存规则") { Task { await model.save() } }
            if let message = model.message { Text(message) }
        }
        .navigationTitle("直链上传规则")
        .task { await model.load() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                model.text = try ManagementImport.text(handle.read(upToCount: ManagementImport.maximumBytes + 1) ?? Data())
            } catch { model.message = error.localizedDescription }
        }
    }
}
