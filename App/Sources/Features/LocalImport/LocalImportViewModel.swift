import Foundation
import CryptoKit
import Observation
import LegadoCore

@Observable
@MainActor
final class LocalImportViewModel {
    private(set) var isImporting = false
    private(set) var importedCount = 0
    private(set) var errors: [String] = []
    private(set) var conflictingURLs: [URL] = []
    private(set) var rules: [TxtTocRule] = []
    private(set) var ruleError: String?
    private let database: AppDatabase
    private let booksDirectory: URL

    init(database: AppDatabase, booksDirectory: URL = URL.documentsDirectory.appendingPathComponent("Books", isDirectory: true)) {
        self.database = database; self.booksDirectory = booksDirectory
    }

    func confirmKeepCopy(_ url: URL) async {
        await importFiles([url], keepBoth: true)
    }

    func importFiles(_ urls: [URL], keepBoth: Bool = false) async {
        guard !isImporting else { return }
        isImporting = true; importedCount = 0; errors = []
        conflictingURLs.removeAll { urls.contains($0) }
        defer { isImporting = false }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let identity = SHA256.hash(data: Data(url.standardizedFileURL.absoluteString.utf8))
                .map { String(format: "%02x", $0) }.joined()
            let directory = booksDirectory.appendingPathComponent(keepBoth ? UUID().uuidString : identity, isDirectory: true)
            let staging = booksDirectory.appendingPathComponent(".import-" + UUID().uuidString, isDirectory: true)
            let backup = booksDirectory.appendingPathComponent(".previous-" + UUID().uuidString, isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: staging)
                EpubParserCache.shared.invalidate(staging.appendingPathComponent(url.lastPathComponent))
                MobiParserCache.shared.invalidate(staging.appendingPathComponent(url.lastPathComponent))
            }
            var published = false, hasBackup = false
            do {
                guard ["txt", "epub", "mobi", "azw3", "pdf"].contains(url.pathExtension.lowercased()) else { throw LocalBookError.unsupportedFile }
                let rules = try await TxtTocRuleRepository(database: database).list(enabledOnly: true)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let stagedFile = staging.appendingPathComponent(url.lastPathComponent)
                let destination = directory.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: stagedFile)
                #if os(macOS)
                let options: URL.BookmarkCreationOptions = scoped ? [.withSecurityScope] : [.minimalBookmark]
                #else
                let options: URL.BookmarkCreationOptions = [.minimalBookmark]
                #endif
                let bookmark = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
                try bookmark.write(to: staging.appendingPathComponent("source.bookmark"), options: .atomic)
                let task = Task.detached(priority: .userInitiated) { try LocalBook.parse(url: stagedFile, rules: rules) }
                var parsed = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                parsed.book.bookUrl = destination.absoluteString
                for index in parsed.chapters.indices {
                    parsed.chapters[index].bookUrl = destination.absoluteString
                    parsed.chapters[index].baseUrl = destination.absoluteString
                }
                if let cover = parsed.cover {
                    try cover.write(to: staging.appendingPathComponent("cover"), options: .atomic)
                    parsed.book.coverUrl = directory.appendingPathComponent("cover").absoluteString
                }
                try Task.checkCancellation()
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.moveItem(at: directory, to: backup); hasBackup = true
                }
                try FileManager.default.moveItem(at: staging, to: directory); published = true
                EpubParserCache.shared.invalidate(destination)
                MobiParserCache.shared.invalidate(destination)
                try await LocalBook.save(book: parsed.book, chapters: parsed.chapters, database: database, keepBoth: keepBoth)
                if hasBackup { try? FileManager.default.removeItem(at: backup) }
                importedCount += 1
            } catch {
                do {
                    if published { try FileManager.default.removeItem(at: directory) }
                    if hasBackup { try FileManager.default.moveItem(at: backup, to: directory) }
                } catch { errors.append("恢复原文件失败：\(error.localizedDescription)") }
                if case LocalBookError.identityConflict = error { conflictingURLs.append(url) }
                errors.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                if error is CancellationError { break }
            }
        }
    }

    func loadRules() async {
        do { rules = try await TxtTocRuleRepository(database: database).list(); ruleError = nil }
        catch { ruleError = error.localizedDescription }
    }

    func saveRule(_ rule: TxtTocRule) async {
        do { try await TxtTocRuleRepository(database: database).save(rule); await loadRules() }
        catch { ruleError = error.localizedDescription }
    }
}
