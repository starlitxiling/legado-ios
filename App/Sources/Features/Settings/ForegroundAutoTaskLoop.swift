import Foundation

@MainActor
final class ForegroundAutoTaskLoop {
    private var task: Task<Void, Never>?
    private var running = false

    func update(active: Bool, enabled: Bool, operation: @escaping @MainActor () async -> Void) {
        let shouldRun = active && enabled
        guard shouldRun != running else { return }
        running = shouldRun
        task?.cancel()
        guard shouldRun else { return }
        let previous = task
        task = Task {
            await previous?.value
            while !Task.isCancelled {
                await operation()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
    }

    func waitUntilStopped() async { await task?.value }
    deinit { task?.cancel() }
}
