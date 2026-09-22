import Foundation
import Observation
import LegadoCore

struct LocalScanDirectory: Codable, Identifiable {
    let id: UUID
    let name: String
    var bookmark: Data
}

@Observable
@MainActor
final class LocalDirectoryScanner {
    private(set) var directories: [LocalScanDirectory] = []
    private(set) var files: [URL] = []
    private(set) var isScanning = false
    var userError: UserFacingError?
    var errorMessage: String? { userError?.displayText }
    private var currentDirectory: UUID?
    private let defaults: UserDefaults
    private let key = "Legado.localImportDirectories"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do { directories = try JSONDecoder().decode([LocalScanDirectory].self, from: data) }
            catch { userError = error.presentation(operation: "读取扫描目录设置", subject: nil) }
        }
    }

    func add(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            #if os(macOS)
            let options: URL.BookmarkCreationOptions = scoped ? [.withSecurityScope] : [.minimalBookmark]
            #else
            let options: URL.BookmarkCreationOptions = [.minimalBookmark]
            #endif
            let bookmark = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
            let directory = LocalScanDirectory(id: UUID(), name: url.lastPathComponent, bookmark: bookmark)
            directories.append(directory)
            try persist()
            await scan(directory.id)
        } catch { userError = error.presentation(operation: "保存扫描目录", subject: url.lastPathComponent) }
    }

    func remove(_ id: UUID) {
        directories.removeAll { $0.id == id }
        if currentDirectory == id { files = []; currentDirectory = nil }
        do { try persist() } catch { userError = error.presentation(operation: "移除扫描目录", subject: id.uuidString) }
    }

    func scan(_ id: UUID) async {
        guard !isScanning else { return }
        isScanning = true; userError = nil; files = []; currentDirectory = id
        defer { isScanning = false }
        do {
            let url = try resolve(id)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let scanning = Task.detached(priority: .userInitiated) { try Self.enumerate(url) }
            files = try await withTaskCancellationHandler { try await scanning.value } onCancel: { scanning.cancel() }
        } catch { userError = error.presentation(operation: "扫描书籍目录", subject: directories.first { $0.id == id }?.name) }
    }

    func importScanned(using model: LocalImportViewModel) async {
        guard let id = currentDirectory else { return }
        do {
            let directory = try resolve(id)
            let scoped = directory.startAccessingSecurityScopedResource()
            defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
            await model.importFiles(files)
        } catch { userError = error.presentation(operation: "打开扫描目录", subject: directories.first { $0.id == id }?.name) }
    }

    private func resolve(_ id: UUID) throws -> URL {
        guard let index = directories.firstIndex(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withoutUI, .withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        let url = try URL(resolvingBookmarkData: directories[index].bookmark, options: options,
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            #if os(macOS)
            let creation: URL.BookmarkCreationOptions = scoped ? [.withSecurityScope] : [.minimalBookmark]
            #else
            let creation: URL.BookmarkCreationOptions = [.minimalBookmark]
            #endif
            directories[index].bookmark = try url.bookmarkData(options: creation, includingResourceValuesForKeys: nil, relativeTo: nil)
            try persist()
        }
        return url
    }

    private func persist() throws { defaults.set(try JSONEncoder().encode(directories), forKey: key) }

    nonisolated static func enumerate(_ root: URL, maximumEntries: Int = 10_000) throws -> [URL] {
        var failure: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in failure = error; return false }) else {
            throw CocoaError(.fileReadUnknown)
        }
        var files: [URL] = [], count = 0
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            count += 1
            guard count <= maximumEntries else { throw BookArchiveError.sizeLimit }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }
            let ext = url.pathExtension.lowercased()
            if values.isRegularFile == true && (LocalBook.fileExtensions.contains(ext) || BookArchive.formats.contains(ext)) { files.append(url) }
        }
        if let failure { throw failure }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
