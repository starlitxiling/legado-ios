import Foundation

/// JSC 宿主方法为同步调用；异步服务不继承调用线程的 executor。
enum HostAsyncBridge {
    private final class ResultBox<Value>: @unchecked Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var result: Result<Value, Error>?

        func finish(_ value: Result<Value, Error>) {
            lock.lock()
            guard result == nil else { lock.unlock(); return }
            result = value
            lock.unlock()
            semaphore.signal()
        }

        func get() throws -> Value {
            lock.lock()
            defer { lock.unlock() }
            return try result!.get()
        }
    }
    static func wait<Value>(_ operation: @escaping @Sendable () async throws -> Value) throws -> Value {
        try Task.checkCancellation()
        let box = ResultBox<Value>()
        let inner = Task.detached {
            await withTaskCancellationHandler {
                do {
                    try Task.checkCancellation()
                    box.finish(.success(try await operation()))
                } catch { box.finish(.failure(error)) }
            } onCancel: {
                box.finish(.failure(CancellationError()))
            }
        }
        // 同步 JSC 栈不能 await 外层取消处理器；UnsafeCurrentTask 仅在此同步闭包内读取。
        withUnsafeCurrentTask { outer in
            guard let outer else { box.semaphore.wait(); return }
            while box.semaphore.wait(timeout: .now() + .milliseconds(10)) == .timedOut {
                if outer.isCancelled {
                    inner.cancel()
                    box.finish(.failure(CancellationError()))
                    break
                }
            }
            if outer.isCancelled { inner.cancel() }
        }
        try Task.checkCancellation()
        return try box.get()
    }
}

public struct HostFileInfo: Sendable {
    public let path: String
    public let exists: Bool
    public let isDirectory: Bool
    public let size: Int
}

public protocol HostDownloadStore: Sendable {
    func save(_ data: Data, path: String) async throws -> String
    func read(_ path: String) async throws -> Data?
    func info(_ path: String) async throws -> HostFileInfo
    func list(_ path: String) async throws -> [String]
    func delete(_ path: String) async throws -> Bool
}

public actor MemoryHostDownloadStore: HostDownloadStore {
    private var files: [String: Data] = [:]
    public init() {}
    public func save(_ data: Data, path: String) throws -> String {
        let path = try HostFilePath.normalize(path)
        files[path] = data
        return path
    }
    public func read(_ path: String) throws -> Data? { files[try HostFilePath.normalize(path)] }
    public func info(_ path: String) throws -> HostFileInfo {
        let path = try HostFilePath.normalize(path)
        let directory = files.keys.contains { $0.hasPrefix(path + "/") }
        return .init(path: path, exists: files[path] != nil || directory, isDirectory: directory, size: files[path]?.count ?? 0)
    }
    public func list(_ path: String) throws -> [String] {
        let prefix = try HostFilePath.normalize(path) + "/"
        return files.keys.filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }.sorted()
    }
    public func delete(_ path: String) throws -> Bool {
        let path = try HostFilePath.normalize(path)
        let keys = files.keys.filter { $0 == path || $0.hasPrefix(path + "/") }
        keys.forEach { files.removeValue(forKey: $0) }
        return !keys.isEmpty
    }
}
