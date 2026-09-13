import Foundation

public enum MobiError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let reason): return "MOBI 解析失败：\(reason)" }
    }
}

struct MobiBytes {
    let data: Data
    init(_ data: Data) { self.data = Data(data) }
    func bytes(_ offset: Int, _ count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else {
            throw MobiError.invalid("记录越界")
        }
        return data.subdata(in: offset..<(offset + count))
    }
    func uint(_ offset: Int, _ count: Int = 4) throws -> Int {
        try bytes(offset, count).reduce(0) { ($0 << 8) | Int($1) }
    }
    func string(_ offset: Int, _ count: Int, _ encoding: String.Encoding = .utf8) throws -> String {
        guard let value = String(data: try bytes(offset, count), encoding: encoding) else {
            throw MobiError.invalid("文本编码无效")
        }
        return value.trimmingCharacters(in: .controlCharacters)
    }
    func variable(_ position: inout Int) throws -> Int {
        var value = 0
        for _ in 0..<4 {
            let byte = try uint(position, 1); position += 1
            value = (value << 7) | (byte & 127)
            if byte & 128 != 0 { return value }
        }
        throw MobiError.invalid("变长整数无终止位")
    }
}

public struct PdbReader {
    private let buffer: MobiBytes
    private let offsets: [Int]
    public let name: String
    public var recordCount: Int { offsets.count - 1 }
    public init(data: Data) throws {
        buffer = MobiBytes(data)
        name = try buffer.string(0, 32, .isoLatin1)
        guard try buffer.string(60, 8) == "BOOKMOBI" else { throw MobiError.invalid("缺少 BOOKMOBI 标识") }
        let count = try buffer.uint(76, 2)
        guard count > 0 else { throw MobiError.invalid("没有记录") }
        let source = buffer
        var records = try (0..<count).map { try source.uint(78 + $0 * 8) }
        records.append(data.count)
        guard records[0] >= 78 + count * 8,
              zip(records, records.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            throw MobiError.invalid("PDB 记录偏移无效")
        }
        offsets = records
    }
    public func getRecordData(_ index: Int) throws -> Data {
        guard index >= 0, index < recordCount else { throw MobiError.invalid("记录编号越界") }
        return try buffer.bytes(offsets[index], offsets[index + 1] - offsets[index])
    }
}
