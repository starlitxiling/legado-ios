import Foundation

public struct WebSocketSearchOptions: Sendable {
    public var scope: String
    public var threadCount: Int
    public var precisionSearch: Bool
    public init(scope: String = "", threadCount: Int = 32, precisionSearch: Bool = false) {
        self.scope = scope; self.threadCount = max(1, threadCount); self.precisionSearch = precisionSearch
    }

    func select(_ sources: [BookSource]) -> [BookSource] {
        let enabled = sources.filter(\.enabled)
        let selected: [BookSource]
        if let separator = scope.range(of: "::") {
            let url = String(scope[separator.upperBound...])
            selected = sources.filter { $0.bookSourceUrl == url }
        } else if !scope.isEmpty {
            let groups = Set(scope.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            selected = enabled.filter { source in
                let normalized = (source.bookSourceGroup ?? "").replacingOccurrences(of: ";", with: ",")
                    .replacingOccurrences(of: "；", with: ",").replacingOccurrences(of: "，", with: ",")
                let membership = Set(normalized.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                return !groups.isDisjoint(with: membership)
            }
        } else { selected = enabled }
        return (selected.isEmpty ? enabled : selected).sorted { $0.customOrder < $1.customOrder }
    }
}

enum WebSocketSearch {
    typealias Operation = (BookSource, String, Bool) async throws -> [SearchBook]
    typealias Sleep = @Sendable (UInt64) async throws -> Void

    static func batches(sources: [BookSource], key: String, options: WebSocketSearchOptions,
                        search: @escaping Operation,
                        sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) }) -> WebSocketRoutes.SearchResults {
        AsyncThrowingStream { continuation in
            let task = Task {
                await withTaskGroup(of: [SearchBook]?.self) { group in
                    var next = 0
                    func enqueue() {
                        let source = sources[next]; next += 1
                        group.addTask {
                            try? await timed(sleep: sleep) { try await search(source, key, options.precisionSearch) }
                        }
                    }
                    for _ in 0..<min(max(1, options.threadCount), sources.count) { enqueue() }
                    for await books in group {
                        guard !Task.isCancelled else { group.cancelAll(); break }
                        if let books { continuation.yield(books) }
                        if next < sources.count { enqueue() }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func timed(sleep: @escaping Sleep, operation: @escaping () async throws -> [SearchBook]) async throws -> [SearchBook] {
        let race = SearchRace()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                let work = Task {
                    do { try Task.checkCancellation(); race.finish(.success(try await operation())) }
                    catch { race.finish(.failure(error)) }
                }
                let timer = Task {
                    do {
                        try await sleep(30_000_000_000)
                        try Task.checkCancellation()
                        race.finish(.failure(URLError(.timedOut)))
                    } catch {
                        if !(error is CancellationError) { race.finish(.failure(error)) }
                    }
                }
                race.attach([work, timer])
            }
        } onCancel: { race.finish(.failure(CancellationError())) }
    }

    // 不等待不响应取消的底层请求；超时与停止仍立即结束这一源的搜索槽位。
    private final class SearchRace: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<[SearchBook], Error>?
        private var continuation: CheckedContinuation<[SearchBook], Error>?
        private var tasks: [Task<Void, Never>] = []

        func install(_ continuation: CheckedContinuation<[SearchBook], Error>) {
            lock.lock()
            let result = result
            if result == nil { self.continuation = continuation }
            lock.unlock()
            if let result { continuation.resume(with: result) }
        }

        func attach(_ tasks: [Task<Void, Never>]) {
            lock.lock()
            let finished = result != nil
            if !finished { self.tasks = tasks }
            lock.unlock()
            if finished { tasks.forEach { $0.cancel() } }
        }

        func finish(_ result: Result<[SearchBook], Error>) {
            lock.lock()
            guard self.result == nil else { lock.unlock(); return }
            self.result = result
            let continuation = continuation, tasks = tasks
            self.continuation = nil; self.tasks = []
            lock.unlock()
            tasks.forEach { $0.cancel() }
            continuation?.resume(with: result)
        }
    }
}

struct WebSocketSearchSnapshot {
    private struct Entry {
        let book: SearchBook
        var origins: Set<String>
    }
    private var entries: [Entry] = []

    mutating func merge(_ books: [SearchBook], key: String) -> [SearchBook] {
        for book in books {
            if let index = entries.firstIndex(where: { $0.book.name == book.name && $0.book.author == book.author }) {
                entries[index].origins.insert(book.origin ?? "")
            } else { entries.append(.init(book: book, origins: [book.origin ?? ""])) }
        }
        func rank(_ book: SearchBook) -> Int {
            if book.name == key || book.author == key { return 0 }
            if book.kind?.contains(key) == true { return 1 }
            if (book.name ?? "").contains(key) || (book.author ?? "").contains(key) { return 2 }
            return 3
        }
        entries = entries.enumerated().sorted { left, right in
            let a = rank(left.element.book), b = rank(right.element.book)
            if a != b { return a < b }
            if a < 3, left.element.origins.count != right.element.origins.count {
                return left.element.origins.count > right.element.origins.count
            }
            return left.offset < right.offset
        }.map(\.element)
        return entries.map(\.book)
    }
}
