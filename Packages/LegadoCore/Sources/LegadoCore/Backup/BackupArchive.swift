import Foundation
import Compression

public enum BackupArchiveError: Error, Equatable {
    case invalidArchive, unsupportedFormat, unsafePath(String), duplicatePath(String), sizeLimit, checksum(String)
}

/// 读取中央目录以支持带 data descriptor 的流式 ZIP；不向磁盘解包。
public struct BackupArchive {
    public let entries: [String: Data]
    public let files: [String: Data]

    public init(data: Data, maximumExpandedSize: Int = 256 * 1024 * 1024) throws {
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ length: Int) throws -> Int {
            guard offset >= 0, offset <= bytes.count - length else { throw BackupArchiveError.invalidArchive }
            return (0..<length).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) }
        }
        func slice(_ offset: Int, _ length: Int) throws -> Data {
            guard offset >= 0, length >= 0, offset <= bytes.count, length <= bytes.count - offset else {
                throw BackupArchiveError.invalidArchive
            }
            return Data(bytes[offset..<(offset + length)])
        }
        guard bytes.count >= 22, maximumExpandedSize >= 0 else { throw BackupArchiveError.invalidArchive }
        let end = try stride(from: bytes.count - 22, through: max(0, bytes.count - 65557), by: -1).first {
            try number($0, 4) == 0x06054b50 && $0 + 22 + number($0 + 20, 2) == bytes.count
        }
        guard let end else { throw BackupArchiveError.invalidArchive }
        let count = try number(end + 10, 2)
        guard try number(end + 4, 2) == 0, try number(end + 6, 2) == 0,
              try number(end + 8, 2) == count, count != 65535 else { throw BackupArchiveError.unsupportedFormat }
        let centralSize = try number(end + 12, 4)
        var cursor = try number(end + 16, 4)
        guard cursor <= end, centralSize == end - cursor else { throw BackupArchiveError.invalidArchive }
        let centralStart = cursor
        var files: [String: Data] = [:]
        var names = Set<String>()
        var total = 0
        for _ in 0..<count {
            guard try number(cursor, 4) == 0x02014b50 else { throw BackupArchiveError.invalidArchive }
            let flags = try number(cursor + 8, 2)
            let method = try number(cursor + 10, 2)
            let crc = try number(cursor + 16, 4)
            let packed = try number(cursor + 20, 4)
            let expanded = try number(cursor + 24, 4)
            let nameLength = try number(cursor + 28, 2)
            let extraLength = try number(cursor + 30, 2)
            let commentLength = try number(cursor + 32, 2)
            let local = try number(cursor + 42, 4)
            guard flags & 0x41 == 0, [0, 8].contains(method), packed != 0xffffffff,
                  expanded != 0xffffffff, local != 0xffffffff, try number(cursor + 34, 2) == 0 else {
                throw BackupArchiveError.unsupportedFormat
            }
            guard expanded <= maximumExpandedSize - total else { throw BackupArchiveError.sizeLimit }
            total += expanded
            let nameData = try slice(cursor + 46, nameLength)
            guard let name = String(data: nameData, encoding: .utf8), !name.isEmpty else {
                throw BackupArchiveError.unsupportedFormat
            }
            guard !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"), !name.contains("\0"),
                  !name.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else {
                throw BackupArchiveError.unsafePath(name)
            }
            guard names.insert(name).inserted else { throw BackupArchiveError.duplicatePath(name) }
            cursor += 46 + nameLength + extraLength + commentLength
            guard cursor <= end, local < centralStart, try number(local, 4) == 0x04034b50,
                  try number(local + 6, 2) == flags, try number(local + 8, 2) == method else {
                throw BackupArchiveError.invalidArchive
            }
            let localNameLength = try number(local + 26, 2)
            guard try slice(local + 30, localNameLength) == nameData else { throw BackupArchiveError.invalidArchive }
            let payloadOffset = try local + 30 + localNameLength + number(local + 28, 2)
            guard payloadOffset <= centralStart, packed <= centralStart - payloadOffset else {
                throw BackupArchiveError.invalidArchive
            }
            let payload = try slice(payloadOffset, packed)
            let output: Data
            if method == 0 {
                guard packed == expanded else { throw BackupArchiveError.invalidArchive }
                output = payload
            } else {
                output = try Self.inflate(payload, size: expanded)
            }
            guard Self.crc32(output) == UInt32(crc) else { throw BackupArchiveError.checksum(name) }
            files[name] = output
        }
        guard cursor == end else { throw BackupArchiveError.invalidArchive }
        self.entries = files
        self.files = files.filter { !$0.key.hasSuffix("/") }
    }

    static func inflate(_ data: Data, size: Int) throws -> Data {
        guard !data.isEmpty else { throw BackupArchiveError.invalidArchive }
        let capacity = max(1, size + 1)
        var output = [UInt8](repeating: 0, count: capacity)
        let decoded = try data.withUnsafeBytes { source in
            try output.withUnsafeMutableBytes { destination in
                var stream = compression_stream(dst_ptr: destination.bindMemory(to: UInt8.self).baseAddress!, dst_size: capacity,
                                                src_ptr: source.bindMemory(to: UInt8.self).baseAddress!, src_size: data.count, state: nil)
                guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                    throw BackupArchiveError.invalidArchive
                }
                defer { compression_stream_destroy(&stream) }
                stream.dst_ptr = destination.bindMemory(to: UInt8.self).baseAddress!
                stream.dst_size = capacity
                stream.src_ptr = source.bindMemory(to: UInt8.self).baseAddress!
                stream.src_size = data.count
                while true {
                    let sourceRemaining = stream.src_size
                    let destinationRemaining = stream.dst_size
                    let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    if status == COMPRESSION_STATUS_END {
                        guard stream.src_size == 0 else { throw BackupArchiveError.invalidArchive }
                        break
                    }
                    // 输入耗尽后仍可能有内部缓冲输出；必须继续到 END，同时拒绝无进展或超量输出。
                    guard status == COMPRESSION_STATUS_OK, stream.dst_size > 0,
                          stream.src_size < sourceRemaining || stream.dst_size < destinationRemaining else {
                        throw BackupArchiveError.invalidArchive
                    }
                }
                return capacity - stream.dst_size
            }
        }
        guard decoded == size else { throw BackupArchiveError.invalidArchive }
        return Data(output.prefix(size))
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xedb88320) }
        }
        return crc ^ 0xffffffff
    }
}
