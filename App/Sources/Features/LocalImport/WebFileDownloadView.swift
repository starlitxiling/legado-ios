import SwiftUI
import LegadoCore

struct WebFileDownloadView: View {
    let book: Book
    let container: AppContainer
    @State private var files: [WebFile] = []
    @State private var source: BookSource?
    @State private var isLoading = false
    @State private var working: String?
    @State private var userError: UserFacingError?
    @State private var message: String?
    @State private var saved: [String: URL] = [:]
    @State private var importer: LocalImportViewModel
    @Environment(\.themeColors) private var colors

    init(book: Book, container: AppContainer) {
        self.book = book; self.container = container
        _importer = State(initialValue: LocalImportViewModel(database: container.database))
    }

    var body: some View {
        List {
            Section {
                Text(book.name ?? "未命名").font(.headline)
                if let author = book.author, !author.isEmpty { Text(author).foregroundStyle(colors.textSecondary) }
                Text("该书源只提供文件下载。可阅读格式会导入书架，其他格式保存到「文件」App 的「阅读 / Downloads」。")
                    .font(.footnote).foregroundStyle(colors.textSecondary)
            }
            if isLoading { ProgressView("正在获取下载地址") }
            if let userError {
                ErrorBanner(error: userError, dismiss: { self.userError = nil }) { _ in Task { await load() } }
            }
            if let message { Text(message).font(.footnote) }
            ForEach(importer.errors, id: \.self) { Text($0).font(.footnote).foregroundStyle(colors.error) }
            Section("文件") {
                ForEach(files) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.name).lineLimit(2)
                            Text(file.isSupported ? "可导入书架" : "仅保存文件").font(.caption).foregroundStyle(colors.textSecondary)
                        }
                        Spacer()
                        if working == file.url { ProgressView() }
                        else if let url = saved[file.url] { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
                        else {
                            Button(file.isSupported ? "导入" : "下载") { Task { await download(file) } }
                                .buttonStyle(.borderless).disabled(working != nil)
                                .accessibilityIdentifier("webfile.download.\(file.name)")
                        }
                    }
                }
            }
        }
        .legadoNavigationTitle("文件下载")
        .task { if files.isEmpty { await load() } }
    }

    private func load() async {
        isLoading = true; userError = nil
        defer { isLoading = false }
        do {
            guard let row = try await container.bookSources.resolveForBookOrigin(book.origin ?? "") else {
                throw ReaderError.missingSource
            }
            let source = try DiscoveryStorage.source(row)
            self.source = source
            let details = try await WebBook(source: source, client: container.httpClient).bookInfoDetails(book)
            files = WebFileResolver.files(book: details.book, downloadURLs: details.downloadURLs)
            if files.isEmpty { throw WebFileError.noDownloads }
        } catch {
            userError = error.presentation(operation: "获取下载地址", subject: book.name, actions: [.retry])
        }
    }

    private func download(_ file: WebFile) async {
        guard let source else { return }
        working = file.url; message = nil; userError = nil
        defer { working = nil }
        do {
            let result = try await WebFileResolver.download(file, source: source, book: book, client: container.httpClient)
            let name = (result.name as NSString).pathExtension.isEmpty ? file.name : result.name
            if WebFile(url: file.url, name: name).isSupported {
                try await importer.importDownloaded(name: name, data: result.data, identity: file.url)
                if importer.importedCount > 0 { message = "已导入书架：\(name)" }
                else if !importer.conflictingURLs.isEmpty { message = "书架中已有同名文件，未重复导入：\(name)" }
            } else {
                let folder = URL.documentsDirectory.appendingPathComponent("Downloads", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = folder.appendingPathComponent(name)
                try result.data.write(to: target, options: .atomic)
                saved[file.url] = target
                message = "已保存到「文件」App：阅读 / Downloads / \(name)"
            }
        } catch {
            userError = error.presentation(operation: "下载文件", subject: file.name)
        }
    }
}
