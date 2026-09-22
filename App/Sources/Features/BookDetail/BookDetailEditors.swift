import SwiftUI
import LegadoCore

struct DetailTextEditor: View {
    let title: String
    let save: (String) async throws -> Void
    @State private var value: String
    @State private var userError: UserFacingError?
    private var error: String? { userError?.displayText }
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: String, save: @escaping (String) async throws -> Void) {
        self.title = title; self.save = save; _value = State(initialValue: initial)
    }

    var body: some View {
        Form {
            TextEditor(text: $value).font(.system(size: 14, design: .monospaced))
                .textInputAutocapitalization(.never).autocorrectionDisabled().frame(minHeight: 240)
            if let error { Text(error).foregroundStyle(.red) }
            Button("保存") {
                saving = true
                Task {
                    defer { saving = false }
                    do { try await save(value); dismiss() }
                    catch { userError = error.presentation(operation: "保存编辑内容", subject: title) }
                }
            }.disabled(saving)
        }.legadoNavigationTitle(title)
    }
}

struct SourceVariableEditor: View {
    let source: String
    let repository: SourceStateRepository
    @State private var value: String?
    @State private var userError: UserFacingError?
    private var error: String? { userError?.displayText }

    var body: some View {
        Group {
            if let value {
                DetailTextEditor(title: "设置源变量", initial: value) { value in
                    let original = try await repository.load(source: source)
                    var updated = original; updated["variable"] = value
                    try await repository.merge(source: source, original: original, updated: updated)
                }
            } else if let error { Text(error).foregroundStyle(.red) }
            else { ProgressView() }
        }.task {
            do { value = try await repository.load(source: source)["variable"] ?? "" }
            catch { userError = error.presentation(operation: "读取书源变量", subject: source) }
        }
    }
}

struct BookDetailEditDestination: View {
    let model: BookDetailViewModel
    let repository: BookshelfRepository
    @State private var row: BookRow?
    @State private var userError: UserFacingError?
    private var error: String? { userError?.displayText }

    var body: some View {
        Group {
            if let row { BookInfoEditView(book: row, repository: repository) }
            else if let error { Text(error).foregroundStyle(.red) }
            else { ProgressView() }
        }.task {
            do { row = try await model.storedBook() }
            catch { userError = error.presentation(operation: "打开书籍编辑", subject: model.book?.name) }
        }
    }
}

struct BookDetailGroupView: View {
    let repository: BookGroupRepository
    let save: (Int64) async -> Void
    @State private var selected: Int64
    @State private var groups: [BookGroupRow] = []
    @State private var userError: UserFacingError?
    private var error: String? { userError?.displayText }
    @State private var saving = false

    init(repository: BookGroupRepository, selected: Int64, save: @escaping (Int64) async -> Void) {
        self.repository = repository; self.save = save; _selected = State(initialValue: selected)
    }

    var body: some View {
        List {
            ForEach(groups, id: \.groupId) { group in
                Toggle(group.groupName, isOn: Binding(get: { selected & group.groupId != 0 }, set: { enabled in
                    if enabled { selected |= group.groupId } else { selected &= ~group.groupId }
                }))
            }
            NavigationLink("管理分组") { GroupEditView(repository: repository) }
            if let error { Text(error).foregroundStyle(.red) }
            Button("保存") { saving = true; Task { await save(selected); saving = false } }.disabled(saving)
        }.legadoNavigationTitle("设置分组").task {
            do { groups = try await repository.list().filter { $0.groupId > 0 } }
            catch { userError = error.presentation(operation: "读取书籍分组", subject: nil) }
        }
    }
}

struct BookUpdateTaskEditor: View {
    let book: Book
    let repository: AutoTaskRuleRepository
    @State private var task = AutoTaskRule()
    @State private var loaded = false
    @State private var userError: UserFacingError?
    private var error: String? { userError?.displayText }
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("任务名称", text: $task.name)
            TextField("Cron", text: Binding(get: { task.cron ?? "" }, set: { task.cron = $0 })).textInputAutocapitalization(.never)
            Toggle("启用", isOn: $task.enable)
            TextEditor(text: $task.script).font(.system(size: 13, design: .monospaced)).frame(minHeight: 160)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if let error { Text(error).foregroundStyle(.red) }
            Button("保存") {
                saving = true
                Task {
                    defer { saving = false }
                    do { try await repository.upsert(task); dismiss() }
                    catch { userError = error.presentation(operation: "保存更新任务", subject: task.name) }
                }
            }.disabled(!loaded || saving || task.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.legadoNavigationTitle("更新任务").task {
            do {
                let existing = try await repository.all()
                task = try BookUpdateTask.find(book: book, tasks: existing) ?? BookUpdateTask.build(book: book, name: "更新：" + (book.name ?? ""))
                if !existing.contains(where: { $0.id == task.id }) {
                    let last = existing.map(\.customOrder).max() ?? -1
                    task.customOrder = last == Int.max ? existing.count : last + 1
                }
                loaded = true
            } catch { userError = error.presentation(operation: "读取更新任务", subject: book.name) }
        }
    }
}

struct LocalBookUploadView: View {
    let book: Book
    let client: any HttpClient
    @State private var name = ""
    @State private var uploading = false
    @State private var message: String?

    var body: some View {
        Form {
            TextField("文件名", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("保存到 WebDav 书籍目录，同名文件不会被覆盖。").font(.footnote)
            if let message { Text(message).textSelection(.enabled) }
            Button("上传") {
                uploading = true; message = nil
                Task {
                    defer { uploading = false }
                    do {
                        guard let local = LocalBook.fileURL(book), name == (name as NSString).lastPathComponent,
                              !name.isEmpty, !name.contains("\\"), name != ".", name != ".." else { throw URLError(.badURL) }
                        let credentials = try SettingsViewModel(store: KeychainStore(), httpClient: client).credentials()
                        let dav = WebDavClient(baseURL: credentials.baseURL, username: credentials.username, password: credentials.password, httpClient: client)
                        let parent = try dav.url(path: AppPreferences.shared.string("webDavDir"))
                        try await dav.ensureCollection(parent)
                        let folder = parent.appendingPathComponent("books", isDirectory: true)
                        try await dav.ensureCollection(folder)
                        let data = try await Task.detached { try Data(contentsOf: local, options: .mappedIfSafe) }.value
                        try await dav.put(data, to: folder.appendingPathComponent(name), overwrite: false)
                        message = "上传完成"
                    } catch { message = error.presentation(operation: "上传本地书", subject: book.name, sourceFile: name)?.displayText }
                }
            }.disabled(uploading || name.isEmpty)
            if uploading { ProgressView() }
        }.legadoNavigationTitle("上传 WebDav").task { name = LocalBook.fileURL(book)?.lastPathComponent ?? "" }
    }
}
