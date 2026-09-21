import Foundation

enum HostFilePath {
    static func normalize(_ path: String) throws -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.contains(where: { $0 != "." }), !parts.contains(".."), !path.contains("\\"), !path.contains(":"), !path.contains("\0") else {
            throw JsEngineError.exception("Unsafe script file path: " + path)
        }
        return "/" + parts.filter { $0 != "." }.joined(separator: "/")
    }
}

public actor DiskHostDownloadStore: HostDownloadStore {
    public static let shared = DiskHostDownloadStore(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LegadoCore/ScriptFiles", isDirectory: true))
    private let directory: URL
    private let maximumSize: Int

    public init(directory: URL, maximumSize: Int = 256 * 1024 * 1024) {
        self.directory = directory.standardizedFileURL
        self.maximumSize = maximumSize
    }

    private func file(_ path: String) throws -> URL {
        let path = try HostFilePath.normalize(path)
        let root = directory.resolvingSymlinksInPath()
        var file = root
        for component in path.split(separator: "/") {
            file.appendPathComponent(String(component))
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                    throw JsEngineError.exception("Symbolic links are not allowed in script storage: " + path)
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile { }
        }
        guard file.path.hasPrefix(root.path + "/") else { throw JsEngineError.exception("Script file escapes storage: " + path) }
        return file
    }

    public func save(_ data: Data, path: String) throws -> String {
        guard data.count <= maximumSize else { throw BookArchiveError.sizeLimit }
        let target = try file(path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        return try HostFilePath.normalize(path)
    }

    public func read(_ path: String) throws -> Data? {
        let target = try file(path)
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumSize else { throw BookArchiveError.sizeLimit }
        return try Data(contentsOf: target)
    }

    public func info(_ path: String) throws -> HostFileInfo {
        let target = try file(path)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
        let size = exists && !isDirectory.boolValue ? try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 : 0
        return .init(path: try HostFilePath.normalize(path), exists: exists, isDirectory: isDirectory.boolValue, size: size)
    }

    public func list(_ path: String) throws -> [String] {
        let target = try file(path)
        guard FileManager.default.fileExists(atPath: target.path) else { return [] }
        let prefix = try HostFilePath.normalize(path)
        return try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil)
            .map { prefix + "/" + $0.lastPathComponent }.sorted()
    }

    public func delete(_ path: String) throws -> Bool {
        let target = try file(path)
        guard FileManager.default.fileExists(atPath: target.path) else { return false }
        try FileManager.default.removeItem(at: target)
        return true
    }
}
