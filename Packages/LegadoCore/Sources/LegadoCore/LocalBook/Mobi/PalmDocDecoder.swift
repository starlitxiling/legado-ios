import Foundation

public enum PalmDocDecoder {
    public static func decompress(_ data: Data, limit: Int = 65536) throws -> Data {
        let input = Array(data)
        var output = Data(), i = 0
        while i < input.count {
            let c = Int(input[i]); i += 1
            switch c {
            case 1...8:
                guard c <= input.count - i else { throw MobiError.invalid("PalmDoc 字面量截断") }
                output.append(contentsOf: input[i..<(i + c)]); i += c
            case 0...127: output.append(UInt8(c))
            case 192...255: output.append(32); output.append(UInt8(c ^ 128))
            default:
                guard i < input.count else { throw MobiError.invalid("PalmDoc 回溯截断") }
                let pair = (c << 8) | Int(input[i]); i += 1
                let length = (pair & 7) + 3, distance = (pair >> 3) & 2047
                guard distance > 0, distance <= output.count else { throw MobiError.invalid("PalmDoc 回溯越界") }
                for _ in 0..<length { output.append(output[output.count - distance]) }
            }
            guard output.count <= limit else { throw MobiError.invalid("解压记录超过限制") }
        }
        return output
    }
}
