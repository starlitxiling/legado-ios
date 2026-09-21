import Foundation

final class SourceLock: @unchecked Sendable {
    static let shared = SourceLock()
    private final class Entry {
        var owner: ObjectIdentifier?
        var depth = 0
        var users = 0
        var epoch = 0
    }
    private let condition = NSCondition()
    private var entries: [String: Entry] = [:]
    private var counters: [String: Int32] = [:]
    private var counterOrder: [String] = []

    func perform(key: String, singleFlight: Bool, timeout: Double, action: () throws -> Void) throws {
        guard timeout.isFinite, (0...300_000).contains(timeout) else { throw JsEngineError.exception("timeoutMs must be in 0...300000") }
        let key = (singleFlight ? "flight:" : "lock:") + key
        let thread = ObjectIdentifier(Thread.current)
        condition.lock()
        let entry = entries[key] ?? Entry()
        entries[key] = entry; entry.users += 1
        let epoch = entry.epoch
        func releaseUser() { entry.users -= 1; if entry.users == 0 { entries.removeValue(forKey: key) } }
        if singleFlight && entry.owner == thread { releaseUser(); condition.unlock(); return }
        let deadline = Date().addingTimeInterval(timeout / 1000)
        while entry.owner != nil && entry.owner != thread {
            if !condition.wait(until: deadline) && entry.owner != nil {
                releaseUser(); condition.unlock()
                throw JsEngineError.exception("source lock timeout: " + key)
            }
        }
        if singleFlight && epoch != entry.epoch { releaseUser(); condition.unlock(); return }
        entry.owner = thread; entry.depth += 1
        condition.unlock()
        var succeeded = false
        defer {
            condition.lock()
            if singleFlight && succeeded { entry.epoch += 1 }
            entry.depth -= 1
            if entry.depth == 0 { entry.owner = nil }
            releaseUser(); condition.broadcast(); condition.unlock()
        }
        try action(); succeeded = true
    }

    func tick(_ key: String) -> Int32 {
        condition.lock(); defer { condition.unlock() }
        let value = counters[key] ?? 0
        counters[key] = value == .max ? 0 : value + 1
        counterOrder.removeAll { $0 == key }; counterOrder.append(key)
        if counterOrder.count > 4096 { counters.removeValue(forKey: counterOrder.removeFirst()) }
        return value
    }
}
