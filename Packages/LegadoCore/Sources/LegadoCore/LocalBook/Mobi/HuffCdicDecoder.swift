import Foundation

public final class HuffCdicDecoder {
    private struct Entry { var data: Data; var decompressed: Bool }
    private let table1: [Int]
    private var mincodeTable = [UInt64](repeating: 0, count: 33)
    private var maxcodeTable = [UInt64](repeating: 0, count: 33)
    private var dictionary: [Entry] = []

    public init(records: [Data]) throws {
        guard let first = records.first else { throw MobiError.invalid("缺少 HUFF 记录") }
        let huff = MobiBytes(first)
        guard try huff.string(0, 4) == "HUFF" else { throw MobiError.invalid("HUFF 标识无效") }
        let offset1 = try huff.uint(8), offset2 = try huff.uint(12)
        table1 = try (0..<256).map { try huff.uint(offset1 + $0 * 4) }
        for i in 1...32 {
            mincodeTable[i] = UInt64(try huff.uint(offset2 + (i - 1) * 8)) << (32 - i)
            maxcodeTable[i] = ((UInt64(try huff.uint(offset2 + (i - 1) * 8 + 4)) + 1) << (32 - i)) - 1
        }
        for data in records.dropFirst() {
            let record = MobiBytes(data)
            guard try record.string(0, 4) == "CDIC" else { throw MobiError.invalid("CDIC 标识无效") }
            let length = try record.uint(4), count = try record.uint(8), bits = try record.uint(12)
            guard bits <= 16, count >= dictionary.count else { throw MobiError.invalid("CDIC 计数无效") }
            let n = min(1 << bits, count - dictionary.count)
            for j in 0..<n {
                let offset = length + (try record.uint(length + j * 2, 2))
                let x = try record.uint(offset, 2)
                dictionary.append(Entry(data: try record.bytes(offset + 2, x & 0x7fff), decompressed: x & 0x8000 != 0))
            }
        }
    }

    public func decompress(_ data: Data, limit: Int = 65536) throws -> Data {
        try decompress(data, limit: limit, active: [])
    }

    private func decompress(_ data: Data, limit: Int, active: Set<Int>) throws -> Data {
        let bytes = Array(data)
        var position = 0, output = Data()
        while position < bytes.count * 8 {
            var code: UInt64 = 0
            for bit in 0..<32 {
                let index = position + bit
                code <<= 1
                if index < bytes.count * 8 { code |= UInt64((bytes[index / 8] >> (7 - index % 8)) & 1) }
            }
            let t1 = table1[Int(code >> 24)]
            var length = t1 & 31
            guard length > 0 else { throw MobiError.invalid("HUFF 码长为零") }
            var maxcode = ((UInt64(t1 >> 8) + 1) << (32 - length)) - 1
            if t1 & 128 == 0 {
                while length <= 32 && code < mincodeTable[length] { length += 1 }
                guard length <= 32 else { throw MobiError.invalid("HUFF 码长越界") }
                maxcode = maxcodeTable[length]
            }
            if length > bytes.count * 8 - position { break }
            position += length
            guard code <= maxcode else { throw MobiError.invalid("HUFF 码无效") }
            let index = Int((maxcode - code) >> (32 - length))
            guard dictionary.indices.contains(index), !active.contains(index), active.count < 64 else {
                throw MobiError.invalid("HUFF 字典越界或循环引用")
            }
            if !dictionary[index].decompressed {
                dictionary[index].data = try decompress(dictionary[index].data, limit: limit, active: active.union([index]))
                dictionary[index].decompressed = true
            }
            guard dictionary[index].data.count <= limit - output.count else { throw MobiError.invalid("HUFF 解压超过限制") }
            output.append(dictionary[index].data)
        }
        return output
    }
}
