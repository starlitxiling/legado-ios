import Foundation

public struct BookshelfRefresh {
    public struct Failure: Sendable { public let bookURL: String; public let message: String }
    public struct Report: Sendable {
        public var updated: [String] = []
        public var failures: [Failure] = []
        public var cancelled = false
    }
    public static func run(bookURLs: [String], maximumConcurrent: Int = 3,
                           update: @escaping @Sendable (String) async throws -> Void) async -> Report {
        let urls = bookURLs.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return await withTaskGroup(of: (String, Result<Void, Error>).self) { group in
            var next = 0, report = Report()
            func enqueue() {
                guard next < urls.count, !Task.isCancelled else { return }
                let url = urls[next]; next += 1
                group.addTask {
                    do { try Task.checkCancellation(); try await update(url); try Task.checkCancellation(); return (url, .success(())) }
                    catch { return (url, .failure(error)) }
                }
            }
            for _ in 0..<min(max(1, maximumConcurrent), urls.count) { enqueue() }
            while let (url, result) = await group.next() {
                switch result {
                case .success: report.updated.append(url)
                case .failure(let error):
                    if error is CancellationError || Task.isCancelled { report.cancelled = true }
                    else { report.failures.append(Failure(bookURL: url, message: error.localizedDescription)) }
                }
                enqueue()
            }
            report.cancelled = report.cancelled || Task.isCancelled
            return report
        }
    }
}
