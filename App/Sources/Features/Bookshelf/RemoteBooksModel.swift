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
    private let filenameScript: () -> String
    private var generation = 0

    init(database: AppDatabase, endpoint: RemoteBooksEndpoint,
         destination: URL = URL.documentsDirectory.appendingPathComponent("Books", isDirectory: true),
         filenameScript: @escaping () -> String = { UserDefaults.standard.string(forKey: "bookImportFileName") ?? "" }) {
        self.filenameScript = filenameScript
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
                errorMessage = error.presentation(operation: "读取远端书籍目录", subject: target.absoluteString)?.displayText
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
        var pendingCover: URL?
        defer {
            if !persisted {
                try? FileManager.default.removeItem(at: folder)
                if let pendingCover { try? FileManager.default.removeItem(at: pendingCover) }
            }
        }
        do {
            let name = file.displayName
            guard Self.supported(name), name == (name as NSString).lastPathComponent,
                  !name.contains("\\"), name != ".", name != ".." else { throw LocalBookError.unsupportedFile }
            if BookArchive.formats.contains((name as NSString).pathExtension.lowercased()) {
                persisted = try await importArchive(file, folder: folder, groupID: groupID)
                if errorMessage == nil && !Task.isCancelled { imported.insert(file.url) }
                return
            }
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
            let filenameScript = filenameScript()
            let parsing = Task.detached(priority: .userInitiated) { try LocalBook.parse(url: local, rules: rules, filenameScript: filenameScript, logger: { AppLogStore.shared.append($0) }) }
            var parsed = try await withTaskCancellationHandler { try await parsing.value } onCancel: { parsing.cancel() }
            parsed.book.origin = origin
            if groupID > 0 { parsed.book.group = groupID }
            if let cover = parsed.cover {
                let coverURL = LocalBook.coverURL(bookURL: parsed.book.bookUrl ?? local.absoluteString, root: destination)
                pendingCover = coverURL
                try FileManager.default.createDirectory(at: coverURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try cover.write(to: coverURL, options: .atomic)
                parsed.book.coverUrl = coverURL.absoluteString
            }
            try Task.checkCancellation()
            try await LocalBook.save(book: parsed.book, chapters: parsed.chapters, database: database)
            persisted = true
            imported.insert(file.url)
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.presentation(operation: "导入远端书籍", sourceFile: file.displayName)?.displayText
                AppLogStore.shared.append("Remote import: " + error.localizedDescription)
            }
        }
    }

    private func importArchive(_ file: WebDavFile, folder: URL, groupID: Int64) async throws -> Bool {
        let data = try await endpoint.client.get(file.url, maximumResponseBytes: 256 * 1024 * 1024)
        let opening = Task.detached(priority: .userInitiated) { try BookArchive(data: data, format: file.url.pathExtension) }
        let archive = try await withTaskCancellationHandler { try await opening.value } onCancel: { opening.cancel() }
        let entries = archive.entries.filter { LocalBook.fileExtensions.contains(($0.name as NSString).pathExtension.lowercased()) }
        guard !entries.isEmpty else { throw BookArchiveError.invalid("No supported books in archive") }
        let repository = BookshelfRepository(database: database)
        var existing = Dictionary((try await repository.all()).filter { $0.origin.hasPrefix("webDav::") }.map { ($0.origin, $0) }, uniquingKeysWith: { first, _ in first })
        let rules = try await TxtTocRuleRepository(database: database).list(enabledOnly: true)
        let filenameScript = filenameScript()
        var persisted = false, failures: [String] = []
        for entry in entries {
            var pendingDirectory: URL?
            var pendingCover: URL?
            do {
                try Task.checkCancellation()
                let remote = CustomUrl(file.url.absoluteString)
                if let serverID = endpoint.serverID { try remote.putAttribute("serverID", serverID) }
                try remote.putAttribute("archiveEntry", entry.name)
                let origin = "webDav::" + remote.description
                if var saved = existing[origin] {
                    saved.type &= ~DiscoveryStorage.hiddenBook
                    if groupID > 0 { saved.group |= groupID }
                    try await repository.update(saved)
                    continue
                }
                let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                pendingDirectory = directory
                let local = directory.appendingPathComponent((entry.name as NSString).lastPathComponent)
                let parsing = Task.detached(priority: .userInitiated) {
                    try archive.read(entry.name).write(to: local, options: .atomic)
                    return try LocalBook.parse(url: local, rules: rules, filenameScript: filenameScript, logger: { AppLogStore.shared.append($0) })
                }
                var parsed = try await withTaskCancellationHandler { try await parsing.value } onCancel: { parsing.cancel() }
                parsed.book.origin = origin
                if groupID > 0 { parsed.book.group = groupID }
                if let cover = parsed.cover {
                    let coverURL = LocalBook.coverURL(bookURL: parsed.book.bookUrl ?? local.absoluteString, root: destination)
                    pendingCover = coverURL
                    try FileManager.default.createDirectory(at: coverURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try cover.write(to: coverURL, options: .atomic)
                    parsed.book.coverUrl = coverURL.absoluteString
                }
                try Task.checkCancellation()
                let saved = try await LocalBook.save(book: parsed.book, chapters: parsed.chapters, database: database)
                existing[origin] = saved
                persisted = true
                pendingDirectory = nil
                pendingCover = nil
            } catch {
                if let pendingDirectory { try? FileManager.default.removeItem(at: pendingDirectory) }
                if let pendingCover { try? FileManager.default.removeItem(at: pendingCover) }
                if error is CancellationError || Task.isCancelled { break }
                if let failure = error.presentation(operation: "导入压缩包书籍", sourceFile: entry.name) { failures.append(failure.displayText) }
            }
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        return persisted
    }

    private nonisolated static func supported(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return LocalBook.fileExtensions.contains(ext) || BookArchive.formats.contains(ext)
    }
}
