import BackgroundTasks
import Foundation
import LegadoCore

@MainActor
final class BookshelfBackgroundRefresh {
    static let identifier = "io.legado.ios.refresh"
    private let database: AppDatabase
    private let client: any HttpClient
    private(set) var errorMessage: String?

    init(database: AppDatabase, client: any HttpClient) {
        self.database = database; self.client = client
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do { try BGTaskScheduler.shared.submit(request); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func handle(_ task: BGAppRefreshTask) {
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
