import Foundation
import CoreFoundation

/// 移植项目 ICU 的中文多字节频率统计；不包含其他语言的识别器。
enum TextEncodingDetector {
    struct Result {
        let name: String
        let encoding: String.Encoding
        let bomSize: Int
    }

    static func detect(_ data: Data, truncated: Bool) -> Result {
        func result(_ name: String, _ encoding: String.Encoding, _ bom: Int = 0) -> Result {
            Result(name: name, encoding: encoding, bomSize: bom)
        }
        if data.starts(with: [0xff, 0xfe, 0, 0]) { return result("UTF-32LE", .utf32LittleEndian, 4) }
        if data.starts(with: [0, 0, 0xfe, 0xff]) { return result("UTF-32BE", .utf32BigEndian, 4) }
        if data.starts(with: [0xff, 0xfe]) { return result("UTF-16LE", .utf16LittleEndian, 2) }
        if data.starts(with: [0xfe, 0xff]) { return result("UTF-16BE", .utf16BigEndian, 2) }
        if data.starts(with: [0xef, 0xbb, 0xbf]) { return result("UTF-8", .utf8, 3) }
        let bytes = [UInt8](data)
        func unicodeConfidence(littleEndian: Bool) -> Int {
            guard bytes.count >= 4 else { return 0 }
            var confidence = 10
            for index in stride(from: 0, to: min(bytes.count - 1, 30), by: 2) {
                let code = littleEndian ? Int(bytes[index]) | Int(bytes[index + 1]) << 8 : Int(bytes[index]) << 8 | Int(bytes[index + 1])
                if code == 0 { confidence -= 10 }
                else if (0x20...0xff).contains(code) || code == 10 { confidence += 10 }
                confidence = min(100, max(0, confidence))
                if confidence == 0 || confidence == 100 { break }
            }
            return confidence
        }
        let le = unicodeConfidence(littleEndian: true), be = unicodeConfidence(littleEndian: false)
        if le > 10 && le > be { return result("UTF-16LE", .utf16LittleEndian) }
        if be > 10 && be > le { return result("UTF-16BE", .utf16BigEndian) }
        if (0...(truncated ? min(3, data.count) : 0)).contains(where: { String(data: data.dropLast($0), encoding: .utf8) != nil }) {
            return result("UTF-8", .utf8)
        }
        let gb = score(bytes, big5: false, truncated: truncated)
        let big5 = score(bytes, big5: true, truncated: truncated)
        if big5.confidence > gb.confidence || (big5.confidence == gb.confidence && big5.common > gb.common) {
            let cf = CFStringConvertIANACharSetNameToEncoding("Big5" as CFString)
            return result("Big5", String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf)))
        }
        let cf = CFStringConvertIANACharSetNameToEncoding("GB18030" as CFString)
        return result(gb.fourByte ? "GB18030" : "GBK", String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf)))
    }

    private static func score(_ bytes: [UInt8], big5: Bool, truncated: Bool) -> (confidence: Int, common: Int, fourByte: Bool) {
        var index = 0, total = 0, multibyte = 0, bad = 0, common = 0, fourByte = false
        let commonChars = big5 ? big5Common : gbCommon
        while index < bytes.count {
            let first = Int(bytes[index]); index += 1; total += 1
            if first <= (big5 ? 0x7f : 0x80) || (big5 && first == 0xff) { continue }
            guard index < bytes.count else { if !truncated { bad += 1 }; break }
            let second = Int(bytes[index]); index += 1
            let valid: Bool
            if !big5 && (0x81...0xfe).contains(first) && (0x30...0x39).contains(second) {
                guard index + 1 < bytes.count else { if !truncated { bad += 1 }; break }
                valid = (0x81...0xfe).contains(Int(bytes[index])) && (0x30...0x39).contains(Int(bytes[index + 1]))
                index += 2
                if valid { fourByte = true }
            } else if big5 {
                valid = second >= 0x40 && second != 0x7f && second != 0xff
            } else {
                valid = (0x81...0xfe).contains(first) && (0x40...0xfe).contains(second) && second != 0x7f
            }
            if valid {
                multibyte += 1
                if commonChars.contains(first << 8 | second) { common += 1 }
            } else { bad += 1 }
            if bad >= 2 && bad * 5 >= multibyte { return (0, common, fourByte) }
        }
        if multibyte <= 10 && bad == 0 { return (multibyte == 0 && total < 10 ? 0 : 10, common, fourByte) }
        if multibyte < 20 * bad { return (0, common, fourByte) }
        let confidence = min(100, Int(log(Double(common + 1)) * (90 / log(Double(max(5, multibyte)) / 4)) + 10))
        return (confidence, common, fourByte)
    }
    private static let big5Common: Set<Int> = [
        0xa140, 0xa141, 0xa142, 0xa143, 0xa147, 0xa149, 0xa175, 0xa176, 0xa440, 0xa446,
        0xa447, 0xa448, 0xa451, 0xa454, 0xa457, 0xa464, 0xa46a, 0xa46c, 0xa477, 0xa4a3,
        0xa4a4, 0xa4a7, 0xa4c1, 0xa4ce, 0xa4d1, 0xa4df, 0xa4e8, 0xa4fd, 0xa540, 0xa548,
        0xa558, 0xa569, 0xa5cd, 0xa5e7, 0xa657, 0xa661, 0xa662, 0xa668, 0xa670, 0xa6a8,
        0xa6b3, 0xa6b9, 0xa6d3, 0xa6db, 0xa6e6, 0xa6f2, 0xa740, 0xa751, 0xa759, 0xa7da,
        0xa8a3, 0xa8a5, 0xa8ad, 0xa8d1, 0xa8d3, 0xa8e4, 0xa8fc, 0xa9c0, 0xa9d2, 0xa9f3,
        0xaa6b, 0xaaba, 0xaabe, 0xaacc, 0xaafc, 0xac47, 0xac4f, 0xacb0, 0xacd2, 0xad59,
        0xaec9, 0xafe0, 0xb0ea, 0xb16f, 0xb2b3, 0xb2c4, 0xb36f, 0xb44c, 0xb44e, 0xb54c,
        0xb5a5, 0xb5bd, 0xb5d0, 0xb5d8, 0xb671, 0xb7ed, 0xb867, 0xb944, 0xbad8, 0xbb44,
        0xbba1, 0xbdd1, 0xc2c4, 0xc3b9, 0xc440, 0xc45f,
    ]
    private static let gbCommon: Set<Int> = [
        0xa1a1, 0xa1a2, 0xa1a3, 0xa1a4, 0xa1b0, 0xa1b1, 0xa1f1, 0xa1f3, 0xa3a1, 0xa3ac,
        0xa3ba, 0xb1a8, 0xb1b8, 0xb1be, 0xb2bb, 0xb3c9, 0xb3f6, 0xb4f3, 0xb5bd, 0xb5c4,
        0xb5e3, 0xb6af, 0xb6d4, 0xb6e0, 0xb7a2, 0xb7a8, 0xb7bd, 0xb7d6, 0xb7dd, 0xb8b4,
        0xb8df, 0xb8f6, 0xb9ab, 0xb9c9, 0xb9d8, 0xb9fa, 0xb9fd, 0xbacd, 0xbba7, 0xbbd6,
        0xbbe1, 0xbbfa, 0xbcbc, 0xbcdb, 0xbcfe, 0xbdcc, 0xbecd, 0xbedd, 0xbfb4, 0xbfc6,
        0xbfc9, 0xc0b4, 0xc0ed, 0xc1cb, 0xc2db, 0xc3c7, 0xc4dc, 0xc4ea, 0xc5cc, 0xc6f7,
        0xc7f8, 0xc8ab, 0xc8cb, 0xc8d5, 0xc8e7, 0xc9cf, 0xc9fa, 0xcab1, 0xcab5, 0xcac7,
        0xcad0, 0xcad6, 0xcaf5, 0xcafd, 0xccec, 0xcdf8, 0xceaa, 0xcec4, 0xced2, 0xcee5,
        0xcfb5, 0xcfc2, 0xcfd6, 0xd0c2, 0xd0c5, 0xd0d0, 0xd0d4, 0xd1a7, 0xd2aa, 0xd2b2,
        0xd2b5, 0xd2bb, 0xd2d4, 0xd3c3, 0xd3d0, 0xd3fd, 0xd4c2, 0xd4da, 0xd5e2, 0xd6d0,
    ]
}
