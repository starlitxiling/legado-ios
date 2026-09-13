import BackgroundTasks
import Foundation
import LegadoCore

@MainActor
final class BookshelfBackgroundRefresh {
    static let identifier = "io.legado.ios.refresh"
    private let database: AppDatabase
    private let client: any HttpClient
    private(set) var errorMessage: String?
    private var registered = false

    init(database: AppDatabase, client: any HttpClient) {
        self.database = database; self.client = client
    }

    func register() {
        guard !registered else { return }
        guard (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])?.contains(Self.identifier) == true else {
            errorMessage = "后台刷新尚未配置允许的任务标识符。"
            return
        }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in
                guard let self else { refreshTask.setTaskCompleted(success: false); return }
                self.handle(refreshTask)
            }
        }
        if registered { schedule() }
        else { errorMessage = "后台刷新注册失败。" }
    }

    func schedule() {
        guard registered else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do { try BGTaskScheduler.shared.submit(request); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func handle(_ task: BGAppRefreshTask) {
        schedule()
        let database = database, client = client
        let work = Task {
            do {
                let report = try await BookshelfRefreshService.refresh(database: database, client: client)
                task.setTaskCompleted(success: !report.cancelled && report.failures.isEmpty)
            } catch { task.setTaskCompleted(success: false) }
        }
        task.expirationHandler = { work.cancel() }
    }
}
