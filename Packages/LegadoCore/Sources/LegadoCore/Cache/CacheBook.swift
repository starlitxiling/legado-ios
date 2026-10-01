import Foundation

public actor CacheBook {
    public enum State: String, Sendable { case queued, running, paused, completed, failed, cancelled }
    public struct Progress: Identifiable, Sendable {
        public let id: UUID
        public let bookURL: String
        public let chapterIndex: Int
        public var state: State
        public var attempts: Int
        public var error: String?
    }
    private struct Key: Hashable { let book: String; let chapter: Int }
    private struct Entry {
        var progress: Progress
        let operation: @Sendable (Int) async throws -> Void
    }
    private let maximumConcurrent: Int
    private let retryLimit: Int
    private let failurePauseThreshold: Int
    private var consecutiveFailures: [String: Int] = [:]
    private var pauseReasons: [String: String] = [:]
    /// Bumped on every state change so observers can skip copying an unchanged snapshot.
    public private(set) var revision = 0
    private let onProgress: @Sendable ([Progress]) -> Void
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private var active: [Key: Task<Void, Never>] = [:]
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// `failurePauseThreshold`: after this many chapters of one book fail in a row, the rest of that book is
    /// paused so a dead or blocked source does not keep retrying every chapter. 0 disables it.
    public init(maximumConcurrent: Int = 3, retryLimit: Int = 2, failurePauseThreshold: Int = 10,
                onProgress: @escaping @Sendable ([Progress]) -> Void = { _ in }) {
        self.maximumConcurrent = max(1, maximumConcurrent)
        self.retryLimit = max(0, retryLimit)
        self.failurePauseThreshold = max(0, failurePauseThreshold)
        self.onProgress = onProgress
    }

    public func enqueue(bookURL: String, chapters: [Int],
                        operation: @escaping @Sendable (Int) async throws -> Void) {
        for index in chapters where index >= 0 {
            let key = Key(book: bookURL, chapter: index)
            if let state = entries[key]?.progress.state, [.queued, .running, .paused].contains(state) { continue }
            if entries[key] == nil { order.append(key) }
            entries[key] = Entry(progress: Progress(id: UUID(), bookURL: bookURL, chapterIndex: index,
                state: .queued, attempts: 0, error: nil), operation: operation)
        }
        pump()
    }

    public func snapshot() -> [Progress] { order.compactMap { entries[$0]?.progress } }

    public func pauseReason(bookURL: String) -> String? { pauseReasons[bookURL] }

    /// Returns nil when nothing changed since `revision`.
    public func changes(since revision: Int) -> (revision: Int, progress: [Progress], pauseReasons: [String: String])? {
        guard revision != self.revision else { return nil }
        return (self.revision, snapshot(), pauseReasons)
    }

    public func pause(bookURL: String) {
        for key in order where key.book == bookURL {
            guard let state = entries[key]?.progress.state, state == .queued || state == .running else { continue }
            entries[key]?.progress.state = .paused
            active[key]?.cancel()
        }
        pump()
    }

    public func resume(bookURL: String) {
        pauseReasons[bookURL] = nil; consecutiveFailures[bookURL] = 0
        for key in order where key.book == bookURL && entries[key]?.progress.state == .paused {
            entries[key]?.progress.state = .queued
        }
        pump()
    }

    public func cancel(bookURL: String) {
        for key in order where key.book == bookURL && entries[key]?.progress.state != .completed {
            entries[key]?.progress.state = .cancelled
            active[key]?.cancel()
        }
        pump()
    }

    public func retry(bookURL: String) {
        pauseReasons[bookURL] = nil; consecutiveFailures[bookURL] = 0
        for key in order where key.book == bookURL {
            guard let state = entries[key]?.progress.state, state == .failed || state == .cancelled else { continue }
            entries[key]?.progress.state = .queued
            entries[key]?.progress.attempts = 0
            entries[key]?.progress.error = nil
        }
        pump()
    }

    public func waitUntilIdle() async {
        if active.isEmpty && !entries.values.contains(where: { $0.progress.state == .queued }) { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func pump() {
        revision &+= 1
        for key in order where active.count < maximumConcurrent {
            guard let entry = entries[key], entry.progress.state == .queued, active[key] == nil else { continue }
            entries[key]?.progress.state = .running
            entries[key]?.progress.attempts += 1
            active[key] = Task {
                let result: Result<Void, Error>
                do {
                    try Task.checkCancellation()
                    try await entry.operation(key.chapter)
                    try Task.checkCancellation()
                    result = .success(())
                } catch { result = .failure(error) }
                finish(key, result: result)
            }
        }
        if active.isEmpty && !entries.values.contains(where: { $0.progress.state == .queued }) {
            let pending = waiters; waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
        onProgress(snapshot())
    }

    private func finish(_ key: Key, result: Result<Void, Error>) {
        active[key] = nil
        if entries[key]?.progress.state == .running {
            switch result {
            case .success:
                entries[key]?.progress.state = .completed
                entries[key]?.progress.error = nil
                consecutiveFailures[key.book] = 0
            case .failure(let error):
                let attempts = entries[key]!.progress.attempts
                entries[key]?.progress.error = error.localizedDescription
                let state: State = error is CancellationError ? .cancelled : (attempts <= retryLimit ? .queued : .failed)
                entries[key]?.progress.state = state
                if state == .failed { recordFailure(book: key.book, error: error) }
            }
        }
        pump()
    }

    private func recordFailure(book: String, error: Error) {
        let count = (consecutiveFailures[book] ?? 0) + 1
        consecutiveFailures[book] = count
        guard failurePauseThreshold > 0, count >= failurePauseThreshold, pauseReasons[book] == nil else { return }
        pauseReasons[book] = "连续 \(count) 章下载失败，已自动暂停：\(error.localizedDescription)"
        for key in order where key.book == book {
            guard let state = entries[key]?.progress.state, state == .queued || state == .running else { continue }
            entries[key]?.progress.state = .paused
            active[key]?.cancel()
        }
    }
}
