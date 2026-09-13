import Foundation

final class MobiTextRecords {
    private let pdb: PdbReader
    private let header: MobiHeader
    private let boundary: Int
    private let decoder: HuffCdicDecoder?
    private let onRecordDecoded: ((Int) -> Void)?
    private let lock = NSLock()
    private var offsets = [0]

    init(pdb: PdbReader, header: MobiHeader, boundary: Int, decoder: HuffCdicDecoder?, onRecordDecoded: ((Int) -> Void)?) {
        self.pdb = pdb; self.header = header; self.boundary = boundary
        self.decoder = decoder; self.onRecordDecoded = onRecordDecoded
    }

    func buildTextRecordOffsets() throws -> Data {
        var raw = Data()
        for index in 0..<header.numTextRecords {
            try Task.checkCancellation()
            let record = try decode(index)
            guard record.count <= 128 * 1024 * 1024 - raw.count else { throw MobiError.invalid("正文超过 128 MB 限制") }
            raw.append(record); offsets.append(raw.count)
        }
        if header.textLength > 0 {
            guard header.textLength <= raw.count else { throw MobiError.invalid("正文截断") }
            raw = Data(raw.prefix(header.textLength))
        }
        return raw
    }

    func getTextRecord(_ index: Int) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        return try decode(index)
    }

    func read(_ ranges: [Range<Int>]) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        var result = Data(), decoded: [Int: Data] = [:]
        for range in ranges {
            guard range.lowerBound >= 0, range.upperBound <= offsets.last! else { throw MobiError.invalid("正文范围越界") }
            var lower = 0, upper = header.numTextRecords
            while lower < upper {
                let middle = (lower + upper) / 2
                if offsets[middle + 1] <= range.lowerBound { lower = middle + 1 } else { upper = middle }
            }
            var index = lower
            while index < header.numTextRecords && offsets[index] < range.upperBound {
                let data: Data
                if let cached = decoded[index] { data = cached }
                else { data = try decode(index); decoded[index] = data }
                let start = max(range.lowerBound, offsets[index]) - offsets[index]
                let end = min(range.upperBound, offsets[index + 1]) - offsets[index]
                result.append(try MobiBytes(data).bytes(start, end - start))
                index += 1
            }
        }
        return result
    }

    private func decode(_ index: Int) throws -> Data {
        guard index >= 0, index < header.numTextRecords else { throw MobiError.invalid("正文记录越界") }
        let data = try removeTrailingEntries(pdb.getRecordData(boundary + index + 1))
        onRecordDecoded?(index)
        let limit = max(4096, header.recordSize)
        switch header.compression {
        case 1: return data
        case 2: return try PalmDocDecoder.decompress(data, limit: limit)
        case 17480:
            guard let decoder else { throw MobiError.invalid("缺少解码字典") }
            return try decoder.decompress(data, limit: limit)
        default: throw MobiError.invalid("不支持压缩类型 \(header.compression)")
        }
    }

    private func removeTrailingEntries(_ data: Data) throws -> Data {
        var end = data.count
        for _ in 0..<(header.trailingFlags >> 1).nonzeroBitCount {
            var size = 0, shift = 0, cursor = end
            repeat {
                guard cursor > 0, shift <= 28 else { throw MobiError.invalid("尾部记录无效") }
                cursor -= 1
                let byte = Int(data[cursor]); size |= (byte & 127) << shift; shift += 7
                if byte & 128 != 0 { break }
            } while true
            guard size > 0, size <= end else { throw MobiError.invalid("尾部记录越界") }
            end -= size
        }
        if header.trailingFlags & 1 != 0 {
            guard end > 0 else { throw MobiError.invalid("多字节尾部为空") }
            end -= Int(data[end - 1] & 3) + 1
        }
        guard end >= 0 else { throw MobiError.invalid("尾部记录越界") }
        return Data(data.prefix(end))
    }
}
