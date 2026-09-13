import Foundation
import CoreFoundation
import SwiftSoup

public enum ResponseDecoder {
    public enum DecodingError: Error, Equatable { case unsupportedCharset(String), invalidBytes(String) }

    public static func encoding(for charset: String) throws -> String.Encoding {
        let name = charset.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cf: CFStringEncoding
        switch name {
        // Foundation 不支持 GB_2312_80 的 NSString 编码编号，使用兼容其字节序列的 GBK。
        case "gbk", "cp936", "gb2312": cf = CFStringEncoding(CFStringEncodings.GBK_95.rawValue)
        case "gb18030": cf = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        case "big5", "big-5": cf = CFStringEncoding(CFStringEncodings.big5.rawValue)
        default: cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        }
        guard cf != kCFStringEncodingInvalidId else { throw DecodingError.unsupportedCharset(charset) }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    public static func decode(_ data: Data, headers: [String: String] = [:], charset: String? = nil) throws -> String {
        let bytes = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(data.dropFirst(3)) : data
        let headerCharset = headers.httpHeader("Content-Type").flatMap(contentTypeCharset)
        let name = charset ?? headerCharset ?? htmlCharset(bytes) ?? "UTF-8"
        let encoding = try encoding(for: name)
        if encoding == .utf8 { return String(decoding: bytes, as: UTF8.self) }
        guard let text = String(data: bytes, encoding: encoding) else { throw DecodingError.invalidBytes(name) }
        return text
    }

    static func contentTypeCharset(_ value: String) -> String? {
        let pattern = #"(?i)charset\s*=\s*["']?([^\s;"']+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    private static func htmlCharset(_ data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        guard let range = text.range(of: #"(?is)<head>[\s\S]*?</head>"#, options: .regularExpression),
              let document = try? SwiftSoup.parseBodyFragment(String(text[range])),
              let metas = try? document.getElementsByTag("meta") else { return nil }
        for meta in metas {
            if let charset = try? meta.attr("charset"), !charset.isEmpty { return charset }
            if (try? meta.attr("http-equiv").lowercased()) == "content-type",
               let content = try? meta.attr("content") {
                let charset: String
                if let range = content.range(of: "charset=", options: .caseInsensitive) {
                    charset = String(content[range.upperBound...])
                } else if let separator = content.firstIndex(of: ";") {
                    charset = String(content[content.index(after: separator)...])
                } else { charset = content }
                if !charset.isEmpty { return charset }
            }
        }
        return nil
    }
}
