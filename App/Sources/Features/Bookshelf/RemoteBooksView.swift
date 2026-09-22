import SwiftUI
import LegadoCore

struct RemoteBooksView: View {
    let database: AppDatabase
    let client: any HttpClient
    let groupID: Int64
    @State private var servers: [Server] = []
    @State private var model: RemoteBooksModel?
    @State private var userError: UserFacingError?
    private var errorMessage: String? { userError?.displayText }
    @State private var task: Task<Void, Never>?

    var body: some View {
        List {
            if let model {
                if model.directories.count > 1 { Button("上级目录", systemImage: "arrow.up") { task = Task { await model.goBack() } }.disabled(model.isLoading) }
                if model.isLoading || model.isImporting { ProgressView(model.isImporting ? "正在导入" : "正在读取目录") }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                if model.files.isEmpty && !model.isLoading { Text("此目录没有支持的书籍文件") }
                ForEach(model.files, id: \.url) { file in
                    Button {
                        task = Task {
                            if file.isDirectory { await model.load(file.url) }
                            else { await model.importBook(file, groupID: groupID) }
                        }
                    } label: {
                        HStack {
                            Image(systemName: file.isDirectory ? "folder" : "book.closed")
                            Text(file.displayName)
                            Spacer()
                            if model.imported.contains(file.url) { Image(systemName: "checkmark") }
                            else if !file.isDirectory { Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).font(.caption) }
                        }
                    }.disabled(model.isLoading || model.isImporting)
                }
            } else {
                Button("默认 WebDAV") { select(nil) }
                ForEach(servers, id: \.id) { server in Button(server.name) { select(server) } }
                NavigationLink("配置 WebDAV 服务器") { ServerSettingsView(database: database, client: client) }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .legadoNavigationTitle("远程书籍")
        .toolbar {
            if let model {
                Button("刷新") { task = Task { await model.load() } }.disabled(model.isLoading || model.isImporting)
                Button("服务器") { task?.cancel(); self.model = nil }.disabled(model.isImporting)
            }
        }
        .task {
            do { servers = try await ServerRepository(database: database).all().filter { $0.type == "WEBDAV" }.sorted { $0.sortNumber < $1.sortNumber } }
            catch { userError = error.presentation(operation: "读取 WebDAV 服务器", subject: nil) }
        }
        .onDisappear { task?.cancel() }
    }

    private func select(_ server: Server?) {
        do {
            let dav: WebDavClient
            let root: URL
            if let server {
                guard let config = try server.webDavConfig() else { throw WebDavError.invalidServer(server.id) }
                root = try WebDavClient.remoteURL(config.url)
                dav = WebDavClient(baseURL: root, username: config.username, password: config.password, httpClient: client)
            } else {
                let credentials = try SettingsViewModel(store: KeychainStore(), httpClient: client).credentials()
                dav = WebDavClient(baseURL: credentials.baseURL, username: credentials.username, password: credentials.password, httpClient: client)
                root = try dav.url(path: AppPreferences.shared.string("webDavDir") + "/books/")
            }
            let selected = RemoteBooksModel(database: database, endpoint: .init(client: dav, root: root, serverID: server?.id))
            model = selected; userError = nil
            task = Task { await selected.load() }
        } catch { userError = error.presentation(operation: "打开远端书籍目录", subject: server?.name) }
    }
}
