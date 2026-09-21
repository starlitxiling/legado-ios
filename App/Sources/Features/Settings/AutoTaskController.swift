import Foundation
import Observation
import LegadoCore

@Observable @MainActor
final class AutoTaskController {
    private(set) var isRunning = false
    private var checkingSchedule = false
    var errorMessage: String?
    private let database: AppDatabase
    private let client: any HttpClient
    private let secrets: any SourceSecretStore
    private let notify: (String, String) async throws -> Void
    init(database: AppDatabase, client: any HttpClient, secrets: any SourceSecretStore,
         notify: @escaping (String, String) async throws -> Void) {
        self.database = database; self.client = client; self.secrets = secrets; self.notify = notify
    }

    func run(_ rule: AutoTaskRule) async {
        guard !isRunning else { return }
        isRunning = true; errorMessage = nil
        defer { isRunning = false }
        do {
            let result = try await AutoTaskRunner.run(rule, database: database, client: client, secrets: secrets) { action in
                try await self.handle(action, taskName: rule.name)
            }
            errorMessage = result.lastError
        } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }

    func runDue() async {
        guard !isRunning, !checkingSchedule else { return }
        checkingSchedule = true
        defer { checkingSchedule = false }
        do {
            for rule in try await AutoTaskRuleRepository(database: database).all() where CronSchedule.isDue(rule, at: Date()) {
                try Task.checkCancellation(); await run(rule)
            }
        } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }

    private func handle(_ action: [String: Any], taskName: String) async throws -> String {
        if (action["type"] as? String ?? "").lowercased() == "notify" {
            let title = String((action["title"] as? String ?? taskName).prefix(200))
            let body = String((action["content"] as? String ?? "").prefix(4000))
            try await notify(title, body); return "Notification delivered"
        }
        let repository = BookshelfRepository(database: database)
        let url = action["bookUrl"] as? String ?? ""
        var selected = try await repository.get(bookUrl: url)
        if selected == nil, let name = action["bookName"] as? String {
            let matches = try await repository.all().filter { $0.name == name && $0.author == (action["bookAuthor"] as? String ?? "") }
            if matches.count == 1 { selected = matches[0] }
        }
        guard let current = selected else { throw JsEngineError.exception("refreshToc book was not found") }
        if action["respectCanUpdate"] as? Bool == true && !current.canUpdate { return current.name + ": updates disabled" }
        var book = try DiscoveryStorage.book(current)
        let previous = book
        let old = try await ChapterRepository(database: database).list(bookUrl: current.bookUrl)
        let chapters: [BookChapter]
        var source: BookSource?
        if LocalBook.isLocal(book) { chapters = try LocalBook.chapterList(book: &book) }
        else {
            guard let row = try await BookSourceRepository(database: database).get(bookSourceUrl: current.origin) else { throw JsEngineError.exception("refreshToc source was not found") }
            source = try DiscoveryStorage.source(row)
            chapters = try await WebBook(source: source!, client: client).chapterList(book: &book, runPreUpdate: true)
        }
        guard !chapters.isEmpty else { throw JsEngineError.exception("refreshToc returned no chapters") }
        _ = try await SourceChangeTransaction.save(book: book, previous: previous,
            chapters: chapters.map { try DiscoveryStorage.row($0, defaults: BookChapterRow()) }, database: database)
        let oldURLs = Set(old.map(\.url)), new = chapters.filter { !oldURLs.contains($0.url ?? "") && !$0.isVolume }
        if let configuration = action["notify"] as? [String: Any], configuration["enable"] as? Bool != false,
           !new.isEmpty, new.count >= (configuration["minCount"] as? Int ?? 1) {
            try await notify(configuration["title"] as? String ?? current.name,
                configuration["content"] as? String ?? "新增 \(new.count) 章")
        }
        if let cache = action["cache"] as? [String: Any], cache["enable"] as? Bool == true, let source {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Legado/ReaderCache", isDirectory: true)
            let web = WebBook(source: source, client: client, configuration: .init(cacheDirectory: directory))
            for chapter in new { try Task.checkCancellation(); _ = try await web.content(book: book, chapter: chapter, includeTitle: false) }
        }
        return current.name + ": +" + String(new.count)
    }
}
