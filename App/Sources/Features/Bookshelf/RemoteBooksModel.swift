import Foundation
import Observation
import LegadoCore

struct RemoteBooksEndpoint: Sendable {
    let client: WebDavClient
    let root: URL
    let serverID: Int64?
}

@Observable
@MainActor
final class RemoteBooksModel {
    private(set) var files: [WebDavFile] = []
    private(set) var directories: [URL] = []
    private(set) var isLoading = false
    private(set) var isImporting = false
    private(set) var errorMessage: String?
    private(set) var imported = Set<URL>()
    private let database: AppDatabase
    private let endpoint: RemoteBooksEndpoint
    private let destination: URL
    private var generation = 0

    init(database: AppDatabase, endpoint: RemoteBooksEndpoint,
         destination: URL = URL.documentsDirectory.appendingPathComponent("Books", isDirectory: true)) {
        self.database = database; self.endpoint = endpoint; self.destination = destination
    }

    func load(_ directory: URL? = nil, parent: Bool = false) async {
        generation += 1
        let request = generation
        let target = directory ?? directories.last ?? endpoint.root
        isLoading = true; errorMessage = nil
        defer { if request == generation { isLoading = false } }
        do {
            let result = try await endpoint.client.propfind(target)
            try Task.checkCancellation()
            guard request == generation else { return }
            let targetPath = target.standardized.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            files = result.filter {
                $0.url.standardized.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) != targetPath &&
                ($0.isDirectory || Self.supported($0.displayName))
            }.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            if parent { if directories.count > 1 { directories.removeLast() } }
            else if directories.last != target { directories.append(target) }
        } catch {
            if request == generation, !Task.isCancelled {
                errorMessage = error.localizedDescription
                AppLogStore.shared.append("Remote listing: " + error.localizedDescription)
            }
        }
    }

    func goBack() async {
        guard directories.count > 1 else { return }
        await load(directories[directories.count - 2], parent: true)
    }

    func importBook(_ file: WebDavFile, groupID: Int64) async {
        guard !isImporting, !file.isDirectory else { return }
        isImporting = true; errorMessage = nil
        defer { isImporting = false }
        let folder = destination.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var persisted = false
        defer { if !persisted { try? FileManager.default.removeItem(at: folder) } }
        do {
            let name = file.displayName
            guard Self.supported(name), name == (name as NSString).lastPathComponent,
                  !name.contains("\\"), name != ".", name != ".." else { throw LocalBookError.unsupportedFile }
            let remote = CustomUrl(file.url.absoluteString)
            if let serverID = endpoint.serverID { try remote.putAttribute("serverID", serverID) }
            let origin = "webDav::" + remote.description
            if let existing = try await BookshelfRepository(database: database).all().first(where: { $0.origin == origin }) {
                var saved = existing
                saved.type &= ~DiscoveryStorage.hiddenBook
                if groupID > 0 { saved.group |= groupID }
                try await BookshelfRepository(database: database).update(saved)
                imported.insert(file.url)
                return
            }
            let data = try await endpoint.client.get(file.url, maximumResponseBytes: 256 * 1024 * 1024)
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let local = folder.appendingPathComponent(name)
            try data.write(to: local, options: .atomic)
            let rules = try await TxtTocRuleRepository(database: database).list(enabledOnly: true)
            let parsing = Task.detached(priority: .userInitiated) { try LocalBook.parse(url: local, rules: rules) }
            var parsed = try await withTaskCancellationHandler { try await parsing.value } onCancel: { parsing.cancel() }
            parsed.book.origin = origin
            if groupID > 0 { parsed.book.group = groupID }
            if let cover = parsed.cover {
                let coverURL = folder.appendingPathComponent("cover")
                try cover.write(to: coverURL, options: .atomic)
                parsed.book.coverUrl = coverURL.absoluteString
            }
            try Task.checkCancellation()
            try await LocalBook.save(book: parsed.book, chapters: parsed.chapters, database: database)
            persisted = true
            imported.insert(file.url)
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = file.displayName + "：" + error.localizedDescription
                AppLogStore.shared.append("Remote import: " + error.localizedDescription)
            }
        }
    }

    private nonisolated static func supported(_ filename: String) -> Bool {
        ["txt", "epub", "umd", "mobi", "azw3", "azw", "pdf"].contains((filename as NSString).pathExtension.lowercased())
    }
}
