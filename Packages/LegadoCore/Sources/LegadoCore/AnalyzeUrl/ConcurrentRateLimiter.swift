import Foundation

/// Kotlin ConcurrentRateLimiter：同书源共享固定时间窗口，计数发生在请求开始前。
public actor ConcurrentRateLimiter {
    public static let shared = ConcurrentRateLimiter()
    private struct Record { var time: Int64; var count: Int; var limit: Int; var interval: Int64 }
    private var records: [String: Record] = [:]
    private let now: @Sendable () -> Int64
    private let sleep: @Sendable (Int64) async throws -> Void

    public init(now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
                sleep: @escaping @Sendable (Int64) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0) * 1_000_000) }) {
        self.now = now
        self.sleep = sleep
    }

    public func acquire(key: String?, rate: String?) async throws {
        guard let key, let rate, !rate.isEmpty, rate != "0" else { try Task.checkCancellation(); return }
        while true {
            try Task.checkCancellation()
            let time = now()
            guard var record = records[key] else {
                let values = parse(rate)
                records[key] = Record(time: time, count: 1, limit: values.0, interval: values.1)
                return
            }
            let next = record.time + record.interval
            if time >= next { record.time = time; record.count = 1; records[key] = record; return }
            if record.count < record.limit { record.count += 1; records[key] = record; return }
            try await sleep(next - time)
        }
    }

    public func updateConcurrentRate(key: String, rate: String) {
        let parts = rate.split(separator: "/", omittingEmptySubsequences: false)
        let limit = parts.count == 2 ? Int32(parts[0]) : 1
        let interval = parts.count <= 2 ? Int32(parts.last ?? "") : nil
        guard let limit, let interval, limit > 0, interval > 0 else { return }
        let old = records[key]
        records[key] = Record(time: old?.time ?? now(), count: old?.count ?? 0, limit: Int(limit), interval: Int64(interval))
    }

    private func parse(_ rate: String) -> (Int, Int64) {
        if let slash = rate.firstIndex(of: "/"), slash > rate.startIndex {
            return (Int(Int32(rate[..<slash]) ?? 1), Int64(Int32(rate[rate.index(after: slash)...]) ?? 0))
        }
        return (1, Int64(Int32(rate) ?? 0))
    }
}
