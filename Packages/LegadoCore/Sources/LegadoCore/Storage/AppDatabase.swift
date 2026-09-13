import Foundation
import GRDB

public struct AppDatabase: Sendable {
    let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) throws {
        try Migrations.migrator().migrate(writer)
        try writer.write { db in try KeyboardAssist.seedIfEmpty(db) }
        self.writer = writer
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue(configuration: configuration()))
    }

    public static func file(at path: String) throws -> AppDatabase {
        try AppDatabase(writer: DatabasePool(path: path, configuration: configuration(observesSuspension: true)))
    }

    public func write<T>(_ updates: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await writer.write(updates)
    }

    /// GRDB 通知作用于进程内所有启用通知监听的数据库。
    public func suspend() {
        NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
    }

    public func resume() {
        NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
    }

    private static func configuration(observesSuspension: Bool = false) -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.observesSuspensionNotifications = observesSuspension
        return configuration
    }
}
