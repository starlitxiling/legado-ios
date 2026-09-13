import Foundation

@MainActor
final class ReadAloudSessionTasks {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var cleanup: Task<Void, Never>?
    var count: Int { tasks.count }
    func start(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID(), barrier = cleanup
        tasks[id] = Task { [weak self] in
            await barrier?.value
            if !Task.isCancelled { await operation() }
            self?.tasks[id] = nil
        }
    }
    func cancelAll(cleanup operation: @escaping @MainActor () async -> Void = {}) {
        let old = Array(tasks.values), previous = cleanup
        tasks.removeAll()
        old.forEach { $0.cancel() }
        cleanup = Task {
            await previous?.value
            await operation()
            for task in old { await task.value }
        }
    }
    func waitForCancellation() async { await cleanup?.value }
    func waitUntilIdle() async {
        await cleanup?.value
        while !tasks.isEmpty { for task in Array(tasks.values) { await task.value } }
    }
}
