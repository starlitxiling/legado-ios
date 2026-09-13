import Foundation
import GRDB

public enum SourceCheckStep: String, Codable, CaseIterable, Sendable {
    case search, detail, toc, content
    public var title: String {
        switch self { case .search: return "搜索"; case .detail: return "详情"; case .toc: return "目录"; case .content: return "正文" }
    }
}

public struct SourceCheckStepResult: Codable, Equatable, Sendable {
    public let step: SourceCheckStep
    public let elapsedMilliseconds: Int64
    public let error: String?
    public let timedOut: Bool
    public var invalidGroup: String? = nil
}

public struct BookSourceCheckState: Codable, Equatable, Sendable, Identifiable {
    public var id: String { sourceURL }
    public let sourceURL: String
    public let sourceName: String
    public let steps: [SourceCheckStepResult]
    public var totalElapsedMilliseconds: Int64? = nil
    public var succeeded: Bool { steps.count == SourceCheckStep.allCases.count && steps.allSatisfy { $0.error == nil } }
    public var elapsedMilliseconds: Int64 { totalElapsedMilliseconds ?? steps.reduce(0) { $0 + $1.elapsedMilliseconds } }
}

public struct SourceChecker {
    private let client: any HttpClient
    private let database: AppDatabase
    private let clock: () -> TimeInterval
    private let secrets: any SourceSecretStore
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    public init(client: any HttpClient, database: AppDatabase,
                clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                secrets: any SourceSecretStore = MemorySourceSecretStore(),
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.client = client; self.database = database; self.clock = clock; self.secrets = secrets; self.sleep = sleep
    }

    public func check(source: BookSource, keyword: String = "我的", timeout: TimeInterval = 180,
                      progress: ((SourceCheckStepResult) async -> Void)? = nil) async throws -> BookSourceCheckState {
        try Task.checkCancellation()
        guard timeout.isFinite, timeout >= 0, timeout <= Double(UInt64.max / 1_000_000_000) else { throw URLError(.badURL) }
        let start = clock()
        let tracker = SourceCheckProgress(start: start)
        let web = WebBook(source: source, client: SourceSessionHttpClient(source: source, database: database, client: client, timeout: timeout, secrets: secrets))
        let steps: [SourceCheckStepResult]
        do {
            if timeout == 0 { throw URLError(.timedOut) }
            steps = try await withThrowingTaskGroup(of: [SourceCheckStepResult].self) { group in
                group.addTask { try await self.runSteps(web: web, keyword: keyword, tracker: tracker, progress: progress) }
                group.addTask { try await self.sleep(timeout); try Task.checkCancellation(); throw URLError(.timedOut) }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch {
            try Task.checkCancellation()
            guard (error as? URLError)?.code == .timedOut else { throw error }
            let failure = tracker.timeout(at: clock())
            steps = failure
            if let last = failure.last { await progress?(last) }
        }
        try Task.checkCancellation()
        let result = BookSourceCheckState(sourceURL: source.bookSourceUrl ?? "", sourceName: source.bookSourceName ?? "", steps: steps,
                                          totalElapsedMilliseconds: Self.milliseconds(clock() - start))
        let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        let respondTime = result.elapsedMilliseconds + (result.succeeded ? 0 : Self.milliseconds(timeout))
        try await database.write { db in
            try db.execute(sql: "INSERT INTO source_state(source, key, value) VALUES (?, 'checkState', ?) ON CONFLICT(source, key) DO UPDATE SET value = excluded.value", arguments: [result.sourceURL, encoded])
            guard let row = try BookSourceRow.fetchOne(db, key: result.sourceURL) else { return }
            var groups = (row.bookSourceGroup ?? "").components(separatedBy: CharacterSet(charactersIn: ",，;；\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && !$0.contains("失效") && $0 != "校验超时" }
            if let failure = result.steps.last?.invalidGroup, !groups.contains(failure) { groups.append(failure) }
            let existing = (row.bookSourceComment ?? "").components(separatedBy: "\n\n").filter { !$0.hasPrefix("// Error: ") }.joined(separator: "\n")
            let comment = result.steps.last?.error.map { "// Error: " + $0 + (existing.isEmpty ? "" : "\n\n" + existing) } ?? existing
            try db.execute(sql: "UPDATE book_sources SET respondTime = ?, bookSourceGroup = ?, bookSourceComment = ? WHERE bookSourceUrl = ?", arguments: [respondTime, groups.joined(separator: ","), comment, result.sourceURL])
        }
        return result
    }

    private func runSteps(web: WebBook, keyword: String, tracker: SourceCheckProgress,
                          progress: ((SourceCheckStepResult) async -> Void)?) async throws -> [SourceCheckStepResult] {
        var steps: [SourceCheckStepResult] = []
        var search: SearchBook?
        var book: Book?
        var chapters: [BookChapter] = []
        for step in SourceCheckStep.allCases {
            try Task.checkCancellation()
            let start = clock()
            tracker.begin(step, at: start)
            var failure: String?
            var invalidGroup: String?
            var timedOut = false
            do {
                switch step {
                case .search:
                    search = try await web.search(key: web.checkKeyword(default: keyword)).first
                    if search == nil { throw WebBookError.missingRule("搜索结果为空") }
                case .detail:
                    guard let search else { throw WebBookError.missingRule("搜索结果") }
                    book = try await web.bookInfo(search)
                case .toc:
                    guard var value = book else { throw WebBookError.missingRule("详情") }
                    chapters = try await web.chapterList(book: &value); book = value
                case .content:
                    guard let book, let chapter = chapters.first(where: { !$0.isVolume }) else { throw WebBookError.emptyToc }
                    _ = try await web.content(book: book, chapter: chapter,
                                              nextChapterUrl: chapters.drop(while: { $0 != chapter }).dropFirst().first?.url)
                }
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                failure = String(describing: error)
                timedOut = (error as? URLError)?.code == .timedOut
                invalidGroup = Self.group(for: error)
            }
            let result = SourceCheckStepResult(step: step, elapsedMilliseconds: Self.milliseconds(clock() - start), error: failure, timedOut: timedOut, invalidGroup: invalidGroup)
            steps.append(result); tracker.finish(result)
            await progress?(result)
            if failure != nil { break }
        }
        return steps
    }

    public func lastResult(source: String) async throws -> BookSourceCheckState? {
        guard let value = try await SourceStateRepository(database: database).load(source: source)["checkState"] else { return nil }
        return try JSONDecoder().decode(BookSourceCheckState.self, from: Data(value.utf8))
    }

    fileprivate static func milliseconds(_ duration: TimeInterval) -> Int64 { max(0, Int64(duration * 1000)) }
    private static func group(for error: Error) -> String {
        if (error as? URLError)?.code == .timedOut { return "校验超时" }
        if error is JsEngineError { return "js失效" }
        switch error as? WebBookError {
        case .emptyToc: return "搜索目录失效"
        case .emptyContent: return "搜索正文失效"
        case .missingRule("搜索结果为空"): return "搜索失效"
        case .missingRule("searchUrl"): return "搜索链接规则为空"
        default: return "网站失效"
        }
    }
}

private final class SourceCheckProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var step = SourceCheckStep.search
    private var started: TimeInterval
    private var completed: [SourceCheckStepResult] = []
    init(start: TimeInterval) { started = start }
    func begin(_ step: SourceCheckStep, at time: TimeInterval) {
        lock.lock(); defer { lock.unlock() }; self.step = step; started = time
    }
    func finish(_ result: SourceCheckStepResult) { lock.lock(); defer { lock.unlock() }; completed.append(result) }
    func timeout(at time: TimeInterval) -> [SourceCheckStepResult] {
        lock.lock(); defer { lock.unlock() }
        var results = completed.filter { $0.step != step }
        results.append(.init(step: step, elapsedMilliseconds: SourceChecker.milliseconds(time - started), error: "校验超时", timedOut: true, invalidGroup: "校验超时"))
        return results
    }
}
