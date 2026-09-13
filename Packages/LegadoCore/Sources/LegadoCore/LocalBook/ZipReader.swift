import Foundation

/// 中央目录只建立索引；读取条目时才解压并校验 CRC，不向磁盘解包。
public final class ZipReader {
    private struct Entry {
        let offset: Int
        let packed: Int
        let expanded: Int
        let method: Int
        let crc: UInt32
    }
    private let data: Data
    private let entries: [String: Entry]
    public let entryNames: Set<String>
    public let byteCount: Int
    private let lock = NSLock()
    private var reads: [String: Int] = [:]

    public convenience init(url: URL, maximumExpandedSize: Int = 256 * 1024 * 1024) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped), maximumExpandedSize: maximumExpandedSize)
    }

    public convenience init(data: Data, maximumExpandedSize: Int = 256 * 1024 * 1024) throws {
        do { try self.init(indexedData: data, maximumExpandedSize: maximumExpandedSize) }
        catch BackupArchiveError.invalidArchive {
            try self.init(indexedData: Self.rebuildDirectory(data), maximumExpandedSize: maximumExpandedSize)
        }
    }

    public func readEntry(_ name: String) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        let payload = data.subdata(in: entry.offset..<(entry.offset + entry.packed))
        let output = entry.method == 0 ? payload : try BackupArchive.inflate(payload, size: entry.expanded)
        guard BackupArchive.crc32(output) == entry.crc else { throw BackupArchiveError.checksum(name) }
        lock.lock(); reads[name, default: 0] += 1; lock.unlock()
        return output
    }

    func readCount(_ name: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return reads[name, default: 0]
    }

    private init(indexedData data: Data, maximumExpandedSize: Int) throws {
        let bytes = data
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
        var files: [String: Entry] = [:]
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
            if method == 0 && packed != expanded { throw BackupArchiveError.invalidArchive }
            files[name] = Entry(offset: payloadOffset, packed: packed, expanded: expanded, method: method, crc: UInt32(crc))
        }
        guard cursor == end else { throw BackupArchiveError.invalidArchive }
        self.data = data; self.entries = files; self.byteCount = data.count
        self.entryNames = Set(files.keys.filter { !$0.hasSuffix("/") })
    }

    private static func rebuildDirectory(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, offset <= bytes.count - count else { throw BackupArchiveError.invalidArchive }
            return (0..<count).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) }
        }
        func field(_ value: Int, _ count: Int) -> Data {
            Data((0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        var cursor = 0, count = 0, central = Data()
        while cursor + 30 <= bytes.count, try number(cursor, 4) == 0x04034b50 {
            let flags = try number(cursor + 6, 2)
            let packed = try number(cursor + 18, 4)
            let expanded = try number(cursor + 22, 4)
            let nameLength = try number(cursor + 26, 2)
            let extraLength = try number(cursor + 28, 2)
            let headerEnd = cursor + 30 + nameLength + extraLength
            // descriptor 和 ZIP64 缺少可靠边界，不能靠扫描签名猜测正文终点。
            guard flags & 8 == 0, packed != 0xffffffff, expanded != 0xffffffff,
                  headerEnd <= bytes.count, packed <= bytes.count - headerEnd, count < 65534 else {
                throw BackupArchiveError.invalidArchive
            }
            central.append(field(0x02014b50, 4))
            central.append(field(20, 2))
            central.append(contentsOf: bytes[(cursor + 4)..<(cursor + 28)])
            central.append(field(0, 2))
            central.append(field(0, 2))
            central.append(field(0, 2))
            central.append(field(0, 2))
            central.append(field(0, 4))
            central.append(field(cursor, 4))
            central.append(contentsOf: bytes[(cursor + 30)..<(cursor + 30 + nameLength)])
            cursor = headerEnd + packed; count += 1
        }
        let nextSignature = cursor + 4 <= bytes.count ? try number(cursor, 4) : 0
        guard count > 0, cursor <= Int(UInt32.max), central.count <= Int(UInt32.max),
              cursor == bytes.count || nextSignature == 0x02014b50 else {
            throw BackupArchiveError.invalidArchive
        }
        var output = Data(bytes[..<cursor])
        output.append(central)
        output.append(field(0x06054b50, 4))
        output.append(field(0, 4))
        output.append(field(count, 2)); output.append(field(count, 2))
        output.append(field(central.count, 4)); output.append(field(cursor, 4))
        output.append(field(0, 2))
        return output
    }
}
