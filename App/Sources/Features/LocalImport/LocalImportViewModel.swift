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

    private var archiveConflicts: [URL: Set<String>] = [:]

    func confirmKeepCopy(_ url: URL) async {
        let entries = archiveConflicts[url]
        await importFiles([url], keepBoth: true, archiveSelection: entries)
    }

    func importFiles(_ urls: [URL], keepBoth: Bool = false, archiveSelection: Set<String>? = nil) async {
        guard !isImporting else { return }
        isImporting = true; importedCount = 0; errors = []
        conflictingURLs.removeAll { urls.contains($0) }
        for url in urls { archiveConflicts[url] = nil }
        defer { isImporting = false }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try Task.checkCancellation()
                if BookArchive.formats.contains(url.pathExtension.lowercased()) {
                    let opening = Task.detached(priority: .userInitiated) { try BookArchive(url: url) }
                    let archive = try await withTaskCancellationHandler { try await opening.value } onCancel: { opening.cancel() }
                    let entries = archive.entries.filter {
                        LocalBook.fileExtensions.contains(($0.name as NSString).pathExtension.lowercased()) &&
                            (archiveSelection == nil || archiveSelection!.contains($0.name))
                    }
                    guard !entries.isEmpty else { throw BookArchiveError.invalid("No supported books in archive") }
                    for entry in entries {
                        try Task.checkCancellation()
                        await importEntry(url, scoped: scoped, archive: archive, entry: entry, keepBoth: keepBoth)
                    }
                } else {
                    await importEntry(url, scoped: scoped, keepBoth: keepBoth)
                }
            } catch {
                if error is CancellationError { break }
                errors.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
    }

    private func importEntry(_ url: URL, scoped: Bool, archive: BookArchive? = nil,
                             entry: BookArchiveEntry? = nil, keepBoth: Bool) async {
        let name = entry.map { ($0.name as NSString).lastPathComponent } ?? url.lastPathComponent
        let source = url.standardizedFileURL.absoluteString + (entry.map { "!" + $0.name } ?? "")
        let identity = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = booksDirectory.appendingPathComponent(keepBoth ? UUID().uuidString : identity, isDirectory: true)
        let staging = booksDirectory.appendingPathComponent(".import-" + UUID().uuidString, isDirectory: true)
        let backup = booksDirectory.appendingPathComponent(".previous-" + UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: staging)
            EpubParserCache.shared.invalidate(staging.appendingPathComponent(name))
            MobiParserCache.shared.invalidate(staging.appendingPathComponent(name))
            UmdParserCache.shared.invalidate(staging.appendingPathComponent(name))
        }
        var published = false, hasBackup = false
        do {
            guard LocalBook.fileExtensions.contains((name as NSString).pathExtension.lowercased()) else { throw LocalBookError.unsupportedFile }
            let rules = try await TxtTocRuleRepository(database: database).list(enabledOnly: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let stagedFile = staging.appendingPathComponent(name)
            let destination = directory.appendingPathComponent(name)
            #if os(macOS)
            let options: URL.BookmarkCreationOptions = scoped ? [.withSecurityScope] : [.minimalBookmark]
            #else
            let options: URL.BookmarkCreationOptions = [.minimalBookmark]
            #endif
            let bookmark = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
            try bookmark.write(to: staging.appendingPathComponent("source.bookmark"), options: .atomic)
            let task = Task.detached(priority: .userInitiated) {
                if let archive, let entry { try archive.read(entry.name).write(to: stagedFile, options: .atomic) }
                else { try FileManager.default.copyItem(at: url, to: stagedFile) }
                return try LocalBook.parse(url: stagedFile, rules: rules)
            }
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
            UmdParserCache.shared.invalidate(destination)
            try await LocalBook.save(book: parsed.book, chapters: parsed.chapters, database: database, keepBoth: keepBoth)
            if hasBackup { try? FileManager.default.removeItem(at: backup) }
            importedCount += 1
        } catch {
            do {
                if published { try FileManager.default.removeItem(at: directory) }
                if hasBackup { try FileManager.default.moveItem(at: backup, to: directory) }
            } catch { errors.append("恢复原文件失败：\(error.localizedDescription)") }
            if case LocalBookError.identityConflict = error {
                if !conflictingURLs.contains(url) { conflictingURLs.append(url) }
                if let entry { archiveConflicts[url, default: []].insert(entry.name) }
            }
            if !(error is CancellationError) { errors.append("\(name)：\(error.localizedDescription)") }
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
