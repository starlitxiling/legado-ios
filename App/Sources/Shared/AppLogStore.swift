import Foundation

final class AppLogStore: @unchecked Sendable {
    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let message: String
    }
    static let shared = AppLogStore()
    private let lock = NSLock()
    private let capacity: Int
    private var entries: [Entry] = []

    init(capacity: Int = 500) { self.capacity = max(1, capacity) }

    func append(_ message: String, at date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        entries.append(Entry(date: date, message: String(message.prefix(2048))))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    func snapshot() -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(keepingCapacity: true)
    }
}
