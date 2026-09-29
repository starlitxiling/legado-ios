import Foundation
import CryptoKit
import Observation
import LegadoCore

@Observable
@MainActor
final class LocalImportViewModel {
    private(set) var isImporting = false
    private(set) var isDownloading = false
    private(set) var importedCount = 0
    private(set) var failures: [UserFacingError] = []
    var errors: [String] { failures.map(\.displayText) }
    private(set) var conflictingURLs: [URL] = []
    private(set) var rules: [TxtTocRule] = []
    private(set) var ruleFailure: UserFacingError?
    var ruleError: String? { ruleFailure?.displayText }
    private let database: AppDatabase
    private let configuredBooksDirectory: URL?
    private var booksDirectory: URL {
        get throws {
            if let configuredBooksDirectory { return configuredBooksDirectory }
            return try Self.storageDirectory(folder: UserDefaults.standard.string(forKey: "Legado.booksFolder") ?? "Books")
        }
    }
    nonisolated static func storageDirectory(folder: String, documents: URL = .documentsDirectory) throws -> URL {
        let name = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSLocalizedDescriptionKey: "书籍目录名称无效，请在设置中填写单个文件夹名称"])
        }
        return documents.appendingPathComponent(name, isDirectory: true)
    }
    private let filenameScript: () -> String

    init(database: AppDatabase, booksDirectory: URL? = nil,
         filenameScript: @escaping () -> String = { UserDefaults.standard.string(forKey: "bookImportFileName") ?? "" }) {
        self.filenameScript = filenameScript
        self.database = database; self.configuredBooksDirectory = booksDirectory
    }

    private var archiveConflicts: [URL: Set<String>] = [:]

    func confirmKeepCopy(_ url: URL) async {
        let entries = archiveConflicts[url]
        await importFiles([url], keepBoth: true, archiveSelection: entries)
    }

    func importFiles(_ urls: [URL], keepBoth: Bool = false, archiveSelection: Set<String>? = nil) async {
        guard !isImporting else { return }
        isImporting = true; importedCount = 0; failures = []
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
                    guard !entries.isEmpty else { throw BookArchiveError.invalid("压缩包中没有支持的书籍文件") }
                    for entry in entries {
                        try Task.checkCancellation()
                        await importEntry(url, scoped: scoped, archive: archive, entry: entry, keepBoth: keepBoth)
                    }
                } else {
                    await importEntry(url, scoped: scoped, keepBoth: keepBoth)
                }
            } catch {
                if error.isCancellation { break }
                report(error, operation: "导入书籍", file: url.lastPathComponent)
            }
        }
    }

    private func importEntry(_ url: URL, scoped: Bool, archive: BookArchive? = nil,
                             entry: BookArchiveEntry? = nil, keepBoth: Bool) async {
        let booksDirectory: URL
        do { booksDirectory = try self.booksDirectory }
        catch { report(error, operation: "打开书籍存储目录", file: url.lastPathComponent); return }
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
        let coverURL = LocalBook.coverURL(bookURL: directory.appendingPathComponent(name).absoluteString, root: booksDirectory)
        var coverWritten = false, previousCover: Data?
        var published = false, hasBackup = false
        do {
            guard LocalBook.fileExtensions.contains((name as NSString).pathExtension.lowercased()) else { throw LocalBookError.unsupportedFile }
            let rules = try await TxtTocRuleRepository(database: database).list(enabledOnly: true)
            let filenameScript = filenameScript()
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
                return try LocalBook.parse(url: stagedFile, rules: rules, filenameScript: filenameScript, logger: { AppLogStore.shared.append($0) })
            }
            var parsed = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            parsed.book.bookUrl = destination.absoluteString
            for index in parsed.chapters.indices {
                parsed.chapters[index].bookUrl = destination.absoluteString
                parsed.chapters[index].baseUrl = destination.absoluteString
            }
            if let cover = parsed.cover {
                if FileManager.default.fileExists(atPath: coverURL.path) { previousCover = try Data(contentsOf: coverURL) }
                try FileManager.default.createDirectory(at: coverURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try cover.write(to: coverURL, options: .atomic)
                coverWritten = true
                parsed.book.coverUrl = coverURL.absoluteString
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
                if coverWritten {
                    if let previousCover { try previousCover.write(to: coverURL, options: .atomic) }
                    else { try FileManager.default.removeItem(at: coverURL) }
                }
            } catch { report(error, operation: "恢复原文件", file: name) }
            if case LocalBookError.identityConflict = error {
                if !conflictingURLs.contains(url) { conflictingURLs.append(url) }
                if let entry { archiveConflicts[url, default: []].insert(entry.name) }
            }
            report(error, operation: "导入书籍", file: name)
        }
    }

    func importOnline(_ text: String, client: any HttpClient = URLSessionHttpClient()) async {
        guard !isImporting, !isDownloading else { return }
        isDownloading = true; failures = []
        defer { isDownloading = false }
        do {
            guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw URLError(.badURL) }
            let response: HttpResponse
            let limit = 256 * 1024 * 1024
            if let limited = client as? any ResponseLimitedHttpClient {
                response = try await limited.send(HttpRequest(url: url), maximumResponseBytes: limit)
            } else { response = try await client.send(HttpRequest(url: url)) }
            guard (200..<300).contains(response.status) else {
                throw WebBookError.httpStatus(response.status, url.absoluteString)
            }
            guard response.body.count <= limit else { throw WebDavError.responseTooLarge }
            let name = Self.downloadedFilename(response)
            let ext = (name as NSString).pathExtension.lowercased()
            guard !name.isEmpty, name == (name as NSString).lastPathComponent, name != ".", name != "..",
                  !name.contains("\\"), !name.contains("\0"),
                  LocalBook.fileExtensions.contains(ext) || BookArchive.formats.contains(ext) else { throw LocalBookError.unsupportedFile }
            try await importDownloaded(name: name, data: response.body, identity: url.absoluteString)
        } catch { report(error, operation: "下载并导入书籍", file: text) }
    }

    func importDownloaded(name: String, data: Data, identity: String) async throws {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = try booksDirectory.appendingPathComponent(".downloads", isDirectory: true).appendingPathComponent(hash)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        try data.write(to: file, options: .atomic)
        await importFiles([file])
    }

    nonisolated static func downloadedFilename(_ response: HttpResponse) -> String {
        let disposition = response.headers.first { $0.key.caseInsensitiveCompare("Content-Disposition") == .orderedSame }?.value ?? ""
        let patterns = [#"(?i)(?:^|;)\s*filename\*\s*=\s*([^;]+)"#, #"(?i)(?:^|;)\s*filename\s*=\s*(?:"([^"]+)"|([^;]+))"#]
        for (patternIndex, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: disposition, range: NSRange(disposition.startIndex..., in: disposition)) else { continue }
            for index in 1..<match.numberOfRanges where match.range(at: index).location != NSNotFound {
                let value = (disposition as NSString).substring(with: match.range(at: index)).trimmingCharacters(in: .whitespaces)
                if patternIndex == 0 {
                    let pieces = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                    if pieces.count == 3, pieces[0].lowercased() == "utf-8",
                       let decoded = String(pieces[2]).removingPercentEncoding { return decoded }
                } else { return value }
            }
        }
        return response.finalURL.lastPathComponent
    }

    private func report(_ error: Error, operation: String, file: String) {
        guard let failure = error.presentation(operation: operation, sourceFile: file) else { return }
        AppLogStore.shared.append(operation + ": " + String(reflecting: error))
        failures.append(failure)
    }

    func loadRules() async {
        do { rules = try await TxtTocRuleRepository(database: database).list(); ruleFailure = nil }
        catch { ruleFailure = error.presentation(operation: "加载 TXT 目录规则") }
    }

    func saveRule(_ rule: TxtTocRule) async {
        do { try await TxtTocRuleRepository(database: database).save(rule); await loadRules() }
        catch { ruleFailure = error.presentation(operation: "保存 TXT 目录规则", subject: rule.name) }
    }
}
