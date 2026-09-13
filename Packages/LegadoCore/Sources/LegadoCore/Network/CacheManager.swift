import Foundation
import CryptoKit

/// 本阶段以文件替代 Kotlin 的字符串缓存数据库；时钟可注入，截止时刻即失效。
public actor CacheManager {
    public static let shared = CacheManager(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("LegadoCore/Cache", isDirectory: true))
    private struct Entry: Codable { let key: String; let value: String; let deadline: Int64 }
    private let directory: URL?
    private let now: @Sendable () -> Int64
    private var entries: [String: Entry] = [:]
    private var memory: [String: String] = [:]
    private var order: [String] = []
    private var memorySize = 0

    public init(directory: URL?, now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.directory = directory
        self.now = now
    }

    public func put(_ key: String, value: String, saveTime: Int32 = 0) throws {
        let entry = Entry(key: key, value: value, deadline: saveTime == 0 ? 0 : now() + Int64(saveTime) * 1000)
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entry).write(to: file(key, directory), options: .atomic)
        } else { entries[key] = entry }
        deleteMemory(key)
        if entry.deadline == 0 { putMemory(key, value: value) }
    }

    public func get(_ key: String, onlyDisk: Bool = false) throws -> String? {
        if !onlyDisk, let value = memory[key] { touch(key); return value }
        let entry: Entry?
        if let directory {
            let path = file(key, directory)
            guard FileManager.default.fileExists(atPath: path.path) else { return nil }
            entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: path))
        } else { entry = entries[key] }
        guard let entry, entry.key == key, entry.deadline == 0 || entry.deadline > now() else { return nil }
        if !onlyDisk && entry.deadline == 0 { putMemory(key, value: entry.value) }
        return entry.value
    }

    public func getInt(_ key: String) throws -> Int32? { try get(key, onlyDisk: true).flatMap(Int32.init) }
    public func getLong(_ key: String) throws -> Int64? { try get(key, onlyDisk: true).flatMap(Int64.init) }
    public func getDouble(_ key: String) throws -> Double? { try get(key, onlyDisk: true).flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    public func getFloat(_ key: String) throws -> Float? { try get(key, onlyDisk: true).flatMap { Float($0.trimmingCharacters(in: .whitespacesAndNewlines)) } }

    public func delete(_ key: String) throws {
        if let directory {
            let path = file(key, directory)
            if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
        }
        entries.removeValue(forKey: key)
        deleteMemory(key)
    }

    private func file(_ key: String, _ directory: URL) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }

    private func touch(_ key: String) { order.removeAll { $0 == key }; order.append(key) }
    private func deleteMemory(_ key: String) {
        if let value = memory.removeValue(forKey: key) { memorySize -= value.utf16.count * 2 }
        order.removeAll { $0 == key }
    }
    private func putMemory(_ key: String, value: String) {
        deleteMemory(key)
        memory[key] = value
        memorySize += value.utf16.count * 2
        touch(key)
        while memorySize > 50 * 1024 * 1024, let oldest = order.first { deleteMemory(oldest) }
    }
}
