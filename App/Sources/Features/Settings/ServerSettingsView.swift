import SwiftUI
import LegadoCore

struct ServerSettingsView: View {
    @State private var model: SubscriptionSettingsModel
    @State private var editing: Server?
    @State private var showEditor = false

    init(database: AppDatabase, client: any HttpClient) {
        _model = State(initialValue: SubscriptionSettingsModel(database: database, client: client))
    }

    var body: some View {
        List {
            ForEach(model.servers, id: \.id) { server in
                Button(server.name) { editing = server; showEditor = true }
                    .swipeActions {
                        Button("删除", role: .destructive) { Task { await model.delete(server) } }
                    }
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("WebDAV 服务器")
        .toolbar { Button("添加") { editing = nil; showEditor = true } }
        .task { await model.load() }
        .sheet(isPresented: $showEditor) { ServerEditor(value: editing ?? Server(), model: model) }
    }
}

private struct ServerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var value: Server
    let model: SubscriptionSettingsModel
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $value.name)
                TextField("WebDAV URL", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("用户名", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("密码", text: $password)
                TextField("排序", value: $value.sortNumber, format: .number)
                if let error = errorMessage ?? model.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("编辑服务器")
            .task {
                do {
                    if let config = try value.webDavConfig() {
                        url = config.url; username = config.username; password = config.password
                    }
                } catch { errorMessage = error.localizedDescription }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            do {
                                try value.setWebDavConfig(.init(url: url, username: username, password: password))
                                if await model.save(value) { dismiss() }
                            } catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
            }
        }
    }
}
