import Foundation

public struct MobiHeader {
    public let compression: Int
    public let numTextRecords: Int
    public let recordSize: Int
    public let textLength: Int
    public let version: Int
    public let encoding: String.Encoding
    public let title: String
    public let author: String
    let resourceStart: Int
    let huffcdic: Int
    let numHuffcdic: Int
    let trailingFlags: Int
    let indx: Int
    let frag: Int
    let skel: Int
    let guide: Int
    let boundary: Int?
    let coverOffset: Int?

    public init(data: Data) throws {
        let b = MobiBytes(data)
        compression = try b.uint(0, 2); textLength = try b.uint(4)
        numTextRecords = try b.uint(8, 2); recordSize = try b.uint(10, 2)
        guard try b.uint(12, 2) == 0 else { throw MobiError.invalid("不支持加密书籍") }
        guard try b.string(16, 4) == "MOBI" else { throw MobiError.invalid("缺少 MOBI 头") }
        let length = try b.uint(20)
        guard length >= 116 else { throw MobiError.invalid("MOBI 头过短") }
        _ = try b.bytes(16, length)
        switch try b.uint(28) {
        case 65001: encoding = .utf8
        case 1252: encoding = .windowsCP1252
        default: throw MobiError.invalid("不支持的编码")
        }
        version = try b.uint(36)
        resourceStart = try b.uint(108); huffcdic = try b.uint(112); numHuffcdic = try b.uint(116)
        trailingFlags = length >= 228 ? try b.uint(240) : 0
        indx = length >= 232 ? try b.uint(244) : 0xffffffff
        frag = version >= 8 ? try b.uint(248) : 0xffffffff
        skel = version >= 8 ? try b.uint(252) : 0xffffffff
        guide = version >= 8 && length >= 248 ? try b.uint(260) : 0xffffffff
        var exth: [Int: [Data]] = [:]
        if try b.uint(128) & 64 != 0 {
            let start = length + 16
            guard try b.string(start, 4) == "EXTH" else { throw MobiError.invalid("EXTH 标识无效") }
            let size = try b.uint(start + 4), count = try b.uint(start + 8)
            guard size >= 12, count <= (size - 12) / 8 else { throw MobiError.invalid("EXTH 长度无效") }
            let e = MobiBytes(try b.bytes(start, size))
            var offset = 12
            for _ in 0..<count {
                let type = try e.uint(offset), size = try e.uint(offset + 4)
                guard size >= 8 else { throw MobiError.invalid("EXTH 记录过短") }
                exth[type, default: []].append(try e.bytes(offset + 8, size - 8)); offset += size
            }
        }
        func number(_ type: Int) throws -> Int? {
            guard let value = exth[type]?.first else { return nil }
            let result = try MobiBytes(value).uint(0)
            return result == 0xffffffff ? nil : result
        }
        let titleOffset = try b.uint(84), titleLength = try b.uint(88)
        let charset = encoding
        title = try exth[503]?.first.map { try MobiBytes($0).string(0, $0.count, charset) }
            ?? b.string(titleOffset, titleLength, charset)
        author = try (exth[100] ?? []).map { try MobiBytes($0).string(0, $0.count, charset) }.joined(separator: ", ")
        boundary = try number(121); coverOffset = try number(201) ?? number(202)
    }
}
