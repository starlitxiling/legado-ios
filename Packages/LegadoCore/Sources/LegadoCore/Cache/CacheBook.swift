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
    private let onProgress: @Sendable ([Progress]) -> Void
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private var active: [Key: Task<Void, Never>] = [:]
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(maximumConcurrent: Int = 3, retryLimit: Int = 2,
                onProgress: @escaping @Sendable ([Progress]) -> Void = { _ in }) {
        self.maximumConcurrent = max(1, maximumConcurrent)
        self.retryLimit = max(0, retryLimit)
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

    public func pause(bookURL: String) {
        for key in order where key.book == bookURL {
            guard let state = entries[key]?.progress.state, state == .queued || state == .running else { continue }
            entries[key]?.progress.state = .paused
            active[key]?.cancel()
        }
        pump()
    }

    public func resume(bookURL: String) {
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
            case .failure(let error):
                let attempts = entries[key]!.progress.attempts
                entries[key]?.progress.error = error.localizedDescription
                entries[key]?.progress.state = error is CancellationError ? .cancelled
                    : (attempts <= retryLimit ? .queued : .failed)
            }
        }
        pump()
    }
}
