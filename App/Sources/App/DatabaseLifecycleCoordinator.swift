import Foundation

final class DatabaseLifecycleCoordinator: NSObject {
    static let readyToRefreshNotification = Notification.Name("Legado.databaseReadyToRefresh")

    private let notificationCenter: NotificationCenter
    private let suspendDatabase: () -> Void
    private let resumeDatabase: () -> Void
    private let lock = NSRecursiveLock()
    private var suspended = false
    private var observers: [NSObjectProtocol] = []

    var isSuspended: Bool {
        lock.lock()
        defer { lock.unlock() }
        return suspended
    }

    init(notificationCenter: NotificationCenter = .default,
         suspend: @escaping () -> Void, resume: @escaping () -> Void) {
        self.notificationCenter = notificationCenter
        suspendDatabase = suspend
        resumeDatabase = resume
        super.init()
    }

    func observe(background: Notification.Name, foreground: Notification.Name) {
        lock.lock()
        defer { lock.unlock() }
        guard observers.isEmpty else { return }
        // queue 为 nil，恢复与刷新通知在原通知的调用栈中按顺序执行。
        observers = [
            notificationCenter.addObserver(forName: background, object: nil, queue: nil) { [weak self] _ in
                self?.didEnterBackground()
            },
            notificationCenter.addObserver(forName: foreground, object: nil, queue: nil) { [weak self] _ in
                self?.willEnterForeground()
            }
        ]
    }

    func didEnterBackground() {
        lock.lock()
        defer { lock.unlock() }
        guard !suspended else { return }
        suspendDatabase()
        suspended = true
    }

    private func willEnterForeground() {
        lock.lock()
        defer { lock.unlock() }
        guard suspended else { return }
        resumeDatabase()
        suspended = false
        notificationCenter.post(name: Self.readyToRefreshNotification, object: self)
    }

    deinit {
        for observer in observers { notificationCenter.removeObserver(observer) }
    }
}
