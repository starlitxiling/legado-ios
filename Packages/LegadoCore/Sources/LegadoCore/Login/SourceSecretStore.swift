import Foundation

public protocol SourceSecretStore: Sendable {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
    func delete(account: String) throws
}

/// 仅用于显式选择临时会话的调用方；App 注入持久化钥匙串。
public final class MemorySourceSecretStore: SourceSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func read(account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }; return values[account]
    }
    public func write(_ value: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }; values[account] = value
    }
    public func delete(account: String) throws {
        lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account)
    }
}
