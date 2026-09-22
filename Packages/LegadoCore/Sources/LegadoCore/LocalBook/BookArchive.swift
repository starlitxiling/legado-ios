import Foundation
import PLzmaSDK
import Unrar

public struct BookArchiveEntry: Equatable, Sendable {
    public let name: String
    public let size: Int
}

public enum BookArchiveError: Error, LocalizedError {
    case invalid(String), sizeLimit, missing(String), unsafePath(String), duplicate(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): return "电子书压缩包损坏：\(reason)"
        case .sizeLimit: return "电子书压缩包超过大小或条目数量限制。"
        case .missing(let name): return "电子书缺少文件：\(name)"
        case .unsafePath(let name): return "电子书包含不安全的路径：\(name)"
        case .duplicate(let name): return "电子书包含重复路径：\(name)"
        }
    }
}

public final class BookArchive {
    public static let formats: Set<String> = ["zip", "rar", "7z"]
    public let entries: [BookArchiveEntry]
    private enum Backend {
        case zip(ZipReader)
        case rar(Unrar.Archive, [String: Unrar.Entry])
        case sevenZip(PLzmaSDK.Decoder, [String: PLzmaSDK.Item])
    }
    private let backend: Backend
    private let lock = NSLock()
    private var temporaryFile: URL?

    public convenience init(data: Data, format: String, password: String? = nil,
                            maximumExpandedSize: Int = 256 * 1024 * 1024, maximumEntries: Int = 10_000) throws {
        guard Self.formats.contains(format.lowercased()) else { throw BookArchiveError.invalid("Unsupported format") }
        guard data.count <= maximumExpandedSize else { throw BookArchiveError.sizeLimit }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + format.lowercased())
        do {
            try data.write(to: temporary, options: .atomic)
            try self.init(url: temporary, password: password, maximumExpandedSize: maximumExpandedSize, maximumEntries: maximumEntries)
            temporaryFile = temporary
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    public init(url: URL, password: String? = nil, maximumExpandedSize: Int = 256 * 1024 * 1024,
                maximumEntries: Int = 10_000) throws {
        try Task.checkCancellation()
        guard maximumExpandedSize > 0, maximumEntries > 0, url.isFileURL,
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumExpandedSize else { throw BookArchiveError.sizeLimit }
        var entries: [BookArchiveEntry] = [], paths = Set<String>(), total: UInt64 = 0
        func entry(_ name: String, size: UInt64, directory: Bool) throws -> String {
            let path = try Self.safePath(name)
            guard paths.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw BookArchiveError.duplicate(path)
            }
            guard paths.count <= maximumEntries, size <= UInt64(maximumExpandedSize) - total else {
                throw BookArchiveError.sizeLimit
            }
            total += size
            if !directory { entries.append(.init(name: path, size: Int(size))) }
            return path
        }
        switch url.pathExtension.lowercased() {
        case "zip":
            let archive = try ZipReader(url: url, maximumExpandedSize: maximumExpandedSize)
            guard archive.totalEntryCount <= maximumEntries else { throw BookArchiveError.sizeLimit }
            for item in archive.orderedEntries { _ = try entry(item.name, size: UInt64(item.size), directory: false) }
            backend = .zip(archive)
        case "rar":
            let archive = try Unrar.Archive(fileURL: url, password: password)
            guard !archive.isVolume else { throw BookArchiveError.invalid("Multi-volume RAR requires a single complete archive") }
            var items: [String: Unrar.Entry] = [:]
            for item in try archive.entries() {
                let path = try entry(item.fileName, size: item.uncompressedSize, directory: item.directory)
                if !item.directory { items[path] = item }
            }
            backend = .rar(archive, items)
        case "7z":
            let decoder = try PLzmaSDK.Decoder(stream: InStream(path: PLzmaSDK.Path(url.path)), fileType: .sevenZ)
            try decoder.setPassword(password)
            guard try decoder.open() else { throw BookArchiveError.invalid("Unable to open 7z archive") }
            let count = try decoder.count()
            guard count <= maximumEntries else { throw BookArchiveError.sizeLimit }
            var items: [String: PLzmaSDK.Item] = [:]
            for index in 0..<count {
                try Task.checkCancellation()
                let item = try decoder.item(at: index)
                let path = try entry(item.path().description, size: item.size, directory: item.isDir)
                if !item.isDir { items[path] = item }
            }
            backend = .sevenZip(decoder, items)
        default: throw BookArchiveError.invalid("Supported formats: zip, rar, 7z")
        }
        self.entries = entries
    }

    deinit { if let temporaryFile { try? FileManager.default.removeItem(at: temporaryFile) } }

    public func read(_ name: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        try Task.checkCancellation()
        guard let entry = entries.first(where: { $0.name == name }) else { throw BookArchiveError.missing(name) }
        let data: Data
        switch backend {
        case .zip(let archive):
            guard let content = try archive.readEntry(name) else { throw BookArchiveError.missing(name) }
            data = content
        case .rar(let archive, let items):
            guard let item = items[name] else { throw BookArchiveError.missing(name) }
            var content = Data(), cancelled = false, exceeded = false
            do {
                try archive.extract(item) { chunk, progress in
                    if Task.isCancelled { cancelled = true; progress.cancel(); return }
                    guard chunk.count <= entry.size - content.count else { exceeded = true; progress.cancel(); return }
                    content.append(chunk)
                }
            } catch {
                if cancelled { throw CancellationError() }
                if exceeded { throw BookArchiveError.sizeLimit }
                throw error
            }
            if exceeded { throw BookArchiveError.sizeLimit }
            data = content
        case .sevenZip(let decoder, let items):
            guard let item = items[name] else { throw BookArchiveError.missing(name) }
            let stream = try OutStream(), streams = try ItemOutStreamArray()
            try streams.add(item: item, stream: stream)
            guard try decoder.extract(itemsToStreams: streams) else { throw BookArchiveError.invalid("7z extraction failed: " + name) }
            data = try stream.copyContent()
        }
        try Task.checkCancellation()
        guard data.count == entry.size else { throw BookArchiveError.invalid("Extracted size mismatch: " + name) }
        return data
    }

    public func extractBooks(to directory: URL) throws -> [URL] {
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            throw BookArchiveError.invalid("Extraction directory already exists")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            var files: [URL] = []
            for entry in entries where LocalBook.fileExtensions.contains((entry.name as NSString).pathExtension.lowercased()) {
                try Task.checkCancellation()
                let file = directory.appendingPathComponent(entry.name)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try read(entry.name).write(to: file, options: .atomic)
                files.append(file)
            }
            return files
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func safePath(_ name: String) throws -> String {
        let name = name.replacingOccurrences(of: "\\", with: "/")
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains(":"), !name.contains("\0"),
              !parts.contains(where: { $0 == "." || $0 == ".." }),
              !parts.dropLast().contains(where: \.isEmpty) else { throw BookArchiveError.unsafePath(name) }
        return name.hasSuffix("/") ? String(name.dropLast()) : name
    }
}
