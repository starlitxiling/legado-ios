import SwiftUI
import LegadoCore

struct SettingsView: View {
    let container: AppContainer
    @State private var model: SettingsViewModel
    @State private var backupModel: BackupViewModel?
    @State private var preferences = AppPreferences.shared

    init(container: AppContainer) {
        self.container = container
        _model = State(initialValue: SettingsViewModel(store: KeychainStore(), httpClient: container.httpClient))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section("WebDAV 账号") {
                TextField("服务器地址", text: $model.address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("用户名", text: $model.username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("密码", text: $model.password)
                Button("保存账号") { model.save() }
                Button("测试连接") { Task { await model.testConnection() } }
                Button("删除保存的账号", role: .destructive) { model.clearCredentials() }
                if model.isTesting { ProgressView("正在测试连接") }
                if let message = model.message { Text(message).foregroundStyle(.secondary) }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .disabled(model.isTesting)
            Section {
                NavigationLink("主题设置") { ThemeSettingsView(preferences: preferences) }
                NavigationLink("其他设置") { OtherSettingsView(container: container, preferences: preferences) }
                NavigationLink("备份设置") { BackupSettingsView(preferences: preferences) }
                NavigationLink("Web 服务") { WebServiceView(model: container.webService) }
                NavigationLink("TXT 目录规则") { TxtTocRulesView(database: container.database) }
                NavigationLink("字典规则") { DictRulesView(database: container.database) }
                NavigationLink("规则订阅") { RuleSubSettingsView(database: container.database, client: container.httpClient) }
                NavigationLink("WebDAV 服务器") { ServerSettingsView(database: container.database, client: container.httpClient) }
                NavigationLink("备份与恢复") {
                    BackupView(container: container, settings: model, model: $backupModel)
                }
                NavigationLink("阅读设置") {
                    Text("字号、行距与主题可在阅读器中设置。")
                        .padding().navigationTitle("阅读设置")
                }
                NavigationLink("关于") { AboutView() }
            }
        }
        .navigationTitle("设置")
        .onAppear { preferences.reload() }
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            LabeledContent("Legado", value: SettingsViewModel.version())
            Section("开源许可") {
                ForEach(OpenSourceLicense.all, id: \.name) { license in
                    NavigationLink {
                        ScrollView { Text(license.text).textSelection(.enabled).padding() }
                            .navigationTitle(license.name)
                    } label: {
                        LabeledContent(license.name, value: license.kind)
                    }
                }
            }
        }
        .navigationTitle("关于")
    }
}
