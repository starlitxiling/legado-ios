import Foundation

public struct WebDavLocalBookRestore: Sendable {
    private let client: WebDavClient
    private let directory: String
    private let destination: URL

    public init(client: WebDavClient, directory: String = "legado", destination: URL) {
        self.client = client
        self.directory = directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.destination = destination
    }

    public func restore(_ book: BookRow, enabled: Bool) async throws -> BookRow {
        var entity = Book()
        entity.bookUrl = book.bookUrl; entity.origin = book.origin
        entity.type = book.type; entity.variable = book.variable
        guard LocalBook.isLocal(entity) else { return book }
        if let local = LocalBook.fileURL(entity), FileManager.default.fileExists(atPath: local.path) { return book }
        let explicit = book.origin.hasPrefix("webDav::") ? String(book.origin.dropFirst("webDav::".count)) : ""
        guard enabled || !explicit.isEmpty else { return book }
        let remote: URL
        if !explicit.isEmpty {
            remote = try WebDavClient.remoteURL(explicit)
        } else {
            let files = try await client.propfind(client.url(path: directory + "/books/"))
            guard let file = files.first(where: { !$0.isDirectory && $0.displayName == book.originName }) else { return book }
            remote = file.url
        }
        let filename = book.originName
        guard !filename.isEmpty, filename == (filename as NSString).lastPathComponent,
              filename != ".", filename != "..", !filename.contains("\\") else { throw LocalBookError.unsupportedFile }
        let response = try await client.get(remote, maximumResponseBytes: 256 * 1024 * 1024)
        try Task.checkCancellation()
        let data: Data
        if !explicit.isEmpty, let entry = try CustomUrl(explicit).getAttr()["archiveEntry"] as? String {
            let reading = Task.detached(priority: .userInitiated) {
                try BookArchive(data: response, format: remote.pathExtension).read(entry)
            }
            data = try await withTaskCancellationHandler { try await reading.value } onCancel: { reading.cancel() }
        } else { data = response }
        // bookUrl 是章节及标注的关联键；恢复路径独立保存，不能改写书籍身份。
        let folder = destination.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(filename)
        do { try data.write(to: file, options: .atomic) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
        var updated = book
        var variables = try book.variable.map { try JSONDecoder().decode([String: String].self, from: Data($0.utf8)) } ?? [:]
        variables["legadoIOSLocalFile"] = file.absoluteString
        updated.variable = String(decoding: try JSONEncoder().encode(variables), as: UTF8.self)
        return updated
    }
}
