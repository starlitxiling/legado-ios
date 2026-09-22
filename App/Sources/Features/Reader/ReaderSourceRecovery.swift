import Foundation
import LegadoCore

struct ReaderRecoveredSource {
    let book: Book
    let chapters: [BookChapter]
    let index: Int
}

enum ReaderSourceRecovery {
    static func find(book: Book, chapterIndex: Int, chapterTitle: String, sources: [BookSource],
                     client: any HttpClient, configuration: WebBookConfiguration,
                     waitForTimeout: @escaping @Sendable () async throws -> Void = {
                         try await Task.sleep(for: .seconds(60))
                     }) async throws -> ReaderRecoveredSource {
        try Task.checkCancellation()
        guard !sources.isEmpty else { throw ReaderSourceRecoveryError.noCandidates }
        let race = ReaderRecoveryRace()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await race.start(continuation: continuation, operation: {
                        try await search(book: book, chapterIndex: chapterIndex, chapterTitle: chapterTitle,
                                         sources: sources, client: client, configuration: configuration)
                    }, waitForTimeout: waitForTimeout)
                }
            }
        } onCancel: {
            Task { await race.finish(.failure(CancellationError())) }
        }
    }

    private static func search(book: Book, chapterIndex: Int, chapterTitle: String, sources: [BookSource],
                               client: any HttpClient, configuration: WebBookConfiguration) async throws -> ReaderRecoveredSource {
        var failures: [String] = []
        let result = await withTaskGroup(of: (ReaderRecoveredSource?, String?).self, returning: ReaderRecoveredSource?.self) { group in
            var remaining = sources.makeIterator()
            func submit(_ source: BookSource) {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let web = WebBook(source: source, client: client, configuration: configuration)
                        var candidate = try await web.preciseSearch(name: book.name ?? "", author: book.author ?? "")
                        if candidate.tocUrl?.isEmpty != false { candidate = try await web.bookInfo(candidate) }
                        let chapters = try await web.chapterList(book: &candidate)
                        guard !chapters.isEmpty else { throw WebBookError.emptyToc }
                        let position = ChapterLocator.locate(oldIndex: chapterIndex, oldTitle: chapterTitle,
                            oldCount: book.totalChapterNum, titles: chapters.map { $0.title ?? "" })
                        let chapter = chapters[min(max(0, position), chapters.count - 1)]
                        let next = chapters.dropFirst(position + 1).first?.url
                        _ = try await web.content(book: candidate, chapter: chapter, nextChapterUrl: next)
                        try Task.checkCancellation()
                        return (ReaderRecoveredSource(book: candidate, chapters: chapters, index: chapter.index), nil)
                    } catch is CancellationError { return (nil, nil) }
                    catch { return (nil, (source.bookSourceName ?? source.bookSourceUrl ?? "Source") + ": " + error.localizedDescription) }
                }
            }
            for _ in 0..<min(max(1, configuration.threadCount), sources.count) {
                if let source = remaining.next() { submit(source) }
            }
            while let (candidate, error) = await group.next() {
                if let candidate { group.cancelAll(); return candidate }
                if let error { failures.append(error) }
                if Task.isCancelled { group.cancelAll(); break }
                if let source = remaining.next() { submit(source) }
            }
            return nil as ReaderRecoveredSource?
        }
        try Task.checkCancellation()
        guard let result else {
            throw NSError(domain: "ReaderSourceRecovery", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "没有可用的替代书源。" + (failures.isEmpty ? "" : "\n" + failures.prefix(5).joined(separator: "\n"))])
        }
        return result
    }
}


enum ReaderSourceRecoveryError: LocalizedError {
    case noCandidates, timedOut
    var errorDescription: String? {
        switch self {
        case .noCandidates: return "没有可用的替代书源，请先导入或启用书源。"
        case .timedOut: return "自动换源已超过 60 秒，已停止查找。请手动换源或稍后重试。"
        }
    }
}

private actor ReaderRecoveryRace {
    private var continuation: CheckedContinuation<ReaderRecoveredSource, Error>?
    private var result: Result<ReaderRecoveredSource, Error>?
    private var tasks: [Task<Void, Never>] = []

    func start(continuation: CheckedContinuation<ReaderRecoveredSource, Error>,
               operation: @escaping @Sendable () async throws -> ReaderRecoveredSource,
               waitForTimeout: @escaping @Sendable () async throws -> Void) {
        if let result { continuation.resume(with: result); return }
        self.continuation = continuation
        tasks = [Task.detached {
            do { await self.finish(.success(try await operation())) }
            catch { await self.finish(.failure(error)) }
        }, Task.detached {
            do {
                try await waitForTimeout()
                await self.finish(.failure(ReaderSourceRecoveryError.timedOut))
            } catch { await self.finish(.failure(error)) }
        }]
    }

    func finish(_ result: Result<ReaderRecoveredSource, Error>) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
        tasks.forEach { $0.cancel() }
        tasks = []
    }
}
