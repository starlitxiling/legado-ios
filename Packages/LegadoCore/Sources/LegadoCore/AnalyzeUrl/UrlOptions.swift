import Foundation
import Darwin

/// AnalyzeUrl 的离线选项状态；URL 编码、JS 和网络执行由后续阶段处理。
public struct UrlOptions {
    public enum ParseStatus: Equatable { case absent, strict, lenient, invalid }
    public enum OptionError: Error { case invalidJSON, illegalArgument }

    public struct Parsed {
        public let url: String
        public let options: UrlOptions
        public let status: ParseStatus
    }

    public private(set) var method = "GET"
    public private(set) var charset: String?
    public var effectiveCharset: String { charset.flatMap { $0.isEmpty ? nil : $0 } ?? "UTF-8" }
    public private(set) var headers: [String: String] = [:]
    public private(set) var body: String?
    public private(set) var origin: String?
    public private(set) var retry: Int32 = 0
    public private(set) var type: String?
    public private(set) var useWebView = false
    public private(set) var webJs: String?
    public private(set) var timeout: Int64?
    public var callTimeout: Int64? { timeout.map(Self.derivedCallTimeoutMillis) }
    public private(set) var followRedirects: Bool?
    public private(set) var dnsIp: String?
    public private(set) var js: String?
    public private(set) var bodyJs: String?
    public private(set) var serverID: Int64?
    public private(set) var webViewDelayTime: Int64 = 0

    public init() {}

    public static func parse(_ rule: String) -> Parsed {
        guard let range = rule.range(of: #"\s*,\s*(?=\{)"#, options: .regularExpression) else {
            return Parsed(url: rule, options: Self(), status: .absent)
        }
        let url = String(rule[..<range.lowerBound])
        let json = String(rule[range.upperBound...])
        for strict in [true, false] {
            if let options = try? decode(json, strict: strict) {
                return Parsed(url: url, options: options, status: strict ? .strict : .lenient)
            }
        }
        return Parsed(url: url, options: Self(), status: .invalid)
    }

    public static func fromJSON(_ json: String) throws -> Self {
        if let options = try? decode(json, strict: true) { return options }
        return try decode(json, strict: false)
    }

    public mutating func setTimeout(_ value: String?) {
        timeout = value.flatMap { Self.requestTimeout(.string($0)) }
    }

    public mutating func setFollowRedirects(_ value: String?) {
        followRedirects = value.flatMap { Self.booleanOption(.string($0)) }
    }

    public mutating func setDnsIp(_ value: String?) {
        dnsIp = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if dnsIp?.isEmpty == true { dnsIp = nil }
    }

    public static func derivedCallTimeoutMillis(_ readTimeoutMillis: Int64) -> Int64 {
        if readTimeoutMillis > Int64(Int32.max) / 2 { return Int64(Int32.max) }
        if readTimeoutMillis <= 30_000 { return 60_000 }
        return readTimeoutMillis * 2
    }

    public static func validateDnsIpProxyCompatibility(proxy: String?, dnsIp: String?) throws {
        let proxy = proxy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dnsIp = dnsIp?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !proxy.isEmpty && !dnsIp.isEmpty { throw OptionError.illegalArgument }
    }

    /// 只调用 inet_pton 校验 IPv6；不允许 DNS 查询或 zone ID。
    public static func parseDnsIpAddresses(_ value: String) throws -> [String] {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { throw OptionError.illegalArgument }
        return try parts.map { part in
            var literal = part
            if literal.hasPrefix("[") && literal.hasSuffix("]") {
                literal = String(literal.dropFirst().dropLast())
            } else if literal.hasPrefix("[") || literal.hasSuffix("]") {
                throw OptionError.illegalArgument
            }
            guard !literal.contains("%"), !literal.contains(where: { $0.isWhitespace }) else {
                throw OptionError.illegalArgument
            }
            if literal.contains(":") {
                var address = in6_addr()
                guard literal.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else {
                    throw OptionError.illegalArgument
                }
                let bytes = withUnsafeBytes(of: &address) { Array($0) }
                if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 255 && bytes[11] == 255 {
                    return bytes.suffix(4).map(String.init).joined(separator: ".")
                }
                return stride(from: 0, to: 16, by: 2).map {
                    String(UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]), radix: 16)
                }.joined(separator: ":")
            }
            let octets = literal.split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4 else { throw OptionError.illegalArgument }
            return try octets.map { octet in
                guard !octet.isEmpty, octet.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                      let number = Int32(octet), (0...255).contains(number) else {
                    throw OptionError.illegalArgument
                }
                return String(number)
            }.joined(separator: ".")
        }
    }

    private static func decode(_ json: String, strict: Bool) throws -> Self {
        var parser = OptionJSONParser(json, strict: strict)
        guard case .object(let entries) = try parser.parse() else { throw OptionError.invalidJSON }
        var result = Self()
        for (key, value) in entries {
            let string = value.optionString
            switch key {
            case "method": result.method = ["POST", "HEAD"].contains(string?.uppercased() ?? "") ? string!.uppercased() : "GET"
            case "charset": result.charset = string
            case "headers":
                let object: OptionJSON?
                if case .string(let json) = value {
                    var parser = OptionJSONParser(json, strict: false)
                    object = (try? parser.parse())?.mapNumbers
                } else { object = value }
                result.headers = [:]
                if case .object(let headers) = object {
                    for (key, value) in headers { result.headers[key] = value.jvmString }
                }
            case "body":
                if case .null = value { result.body = nil }
                else if case .string(let string) = value { result.body = string }
                else { result.body = value.json(pretty: true, omitNulls: true) }
            case "origin": result.origin = string
            case "retry":
                if let integer = try value.integer() {
                    guard let retry = Int32(exactly: integer) else { throw OptionError.invalidJSON }
                    result.retry = retry
                } else { result.retry = 0 }
            case "type": result.type = string
            case "webView":
                switch value {
                case .null, .bool(false), .string(""), .string("false"): result.useWebView = false
                default: result.useWebView = true
                }
            case "webJs": result.webJs = string
            case "timeout": result.timeout = requestTimeout(value)
            case "followRedirects": result.followRedirects = booleanOption(value)
            case "dnsIp", "resolveIp": result.dnsIp = string
            case "js": result.js = string
            case "bodyJs": result.bodyJs = string
            case "serverID": result.serverID = try value.integer()
            case "webViewDelayTime": result.webViewDelayTime = max(0, try value.integer() ?? 0)
            default: break
            }
        }
        return result
    }

    private static func requestTimeout(_ value: OptionJSON) -> Int64? {
        let integer: Int64?
        switch value {
        case .string(let string): integer = Int64(string.trimmingCharacters(in: .whitespacesAndNewlines))
        case .number: integer = try? value.integer()
        default: integer = nil
        }
        return integer.flatMap { (1...Int64(Int32.max)).contains($0) ? $0 : nil }
    }

    private static func booleanOption(_ value: OptionJSON) -> Bool? {
        switch value {
        case .bool(let bool): return bool
        case .number(let string):
            switch Double(string) { case 0: return false; case 1: return true; default: return nil }
        case .string(let string):
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        default: return nil
        }
    }
}

// 对象保留输入顺序，兼容别名覆盖与 Gson body 序列化。
private indirect enum OptionJSON {
    case null, bool(Bool), number(String), string(String), array([OptionJSON]), object([(String, OptionJSON)])

    var optionString: String? {
        switch self {
        case .null: return nil
        case .string(let value), .number(let value): return value
        case .bool(let value): return String(value)
        default: return json()
        }
    }

    var jvmString: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return Self.numberString(value)
        case .array(let values): return "[" + values.map(\.jvmString).joined(separator: ", ") + "]"
        case .object(let entries): return "{" + entries.map { $0 + "=" + $1.jvmString }.joined(separator: ", ") + "}"
        default: return json()
        }
    }

    private static func numberString(_ value: String) -> String {
        if let integer = Int64(value) { return String(integer) }
        guard let number = Double(value) else { return value }
        if number.isNaN { return "NaN" }
        let sign = number.sign == .minus ? "-" : ""
        if number.isInfinite { return sign + "Infinity" }
        if number == 0 { return sign + "0.0" }

        func decimal(_ text: String) -> (digits: String, exponent: Int) {
            let parts = text.lowercased().split(separator: "e")
            let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
            var digits = mantissa.joined()
            var exponent = mantissa[0].count - 1 + (parts.count == 2 ? Int(parts[1])! : 0)
            while digits.first == "0" { digits.removeFirst(); exponent -= 1 }
            while digits.last == "0" { digits.removeLast() }
            return (digits, exponent)
        }
        var (digits, exponent) = decimal(String(abs(number)))
        // Double.toString 对最短一位有效数字还比较两位候选，例如最小次正规数为 4.9E-324。
        if digits.count == 1 {
            (digits, exponent) = decimal(String(format: "%.1e", locale: Locale(identifier: "en_US_POSIX"), abs(number)))
        }
        if exponent < -3 || exponent >= 7 {
            return sign + String(digits.prefix(1)) + "." + (digits.count == 1 ? "0" : String(digits.dropFirst())) + "E" + String(exponent)
        }
        let point = exponent + 1
        if point <= 0 { return sign + "0." + String(repeating: "0", count: -point) + digits }
        if point >= digits.count { return sign + digits + String(repeating: "0", count: point - digits.count) + ".0" }
        return sign + digits.prefix(point) + "." + digits.dropFirst(point)
    }

    var mapNumbers: OptionJSON {
        switch self {
        case .number(let value):
            if let integer = Int64(value) { return .number(String(integer)) }
            if let number = Double(value), number.isFinite,
               let integer = Int64(exactly: number.rounded(.towardZero)), ceil(number) == Double(integer) {
                return .number(String(integer))
            }
            return self
        case .array(let values): return .array(values.map(\.mapNumbers))
        case .object(let entries): return .object(entries.map { ($0, $1.mapNumbers) })
        default: return self
        }
    }

    func integer() throws -> Int64? {
        switch self {
        case .null: return nil
        case .number(let value), .string(let value):
            if let integer = Int64(value) { return integer }
            if let number = Double(value), number.isFinite {
                let integer: Int64
                if number >= Double(Int64.max) { integer = .max }
                else if number <= Double(Int64.min) { integer = .min }
                else { integer = Int64(number) }
                // Gson nextLong 在 JVM 饱和转换后，把结果提升回 Double 检查精度。
                if Double(integer) == number { return integer }
            }
            throw UrlOptions.OptionError.invalidJSON
        default: throw UrlOptions.OptionError.invalidJSON
        }
    }

    func json(pretty: Bool = false, omitNulls: Bool = false, depth: Int = 0) -> String {
        func quote(_ value: String) -> String {
            var result = "\""
            for scalar in value.unicodeScalars {
                switch scalar.value {
                case 34: result += "\\\""
                case 92: result += "\\\\"
                case 8: result += "\\b"
                case 9: result += "\\t"
                case 10: result += "\\n"
                case 12: result += "\\f"
                case 13: result += "\\r"
                case 0...31, 0x2028, 0x2029: result += String(format: "\\u%04x", scalar.value)
                default: result.unicodeScalars.append(scalar)
                }
            }
            return result + "\""
        }
        let indent = String(repeating: "  ", count: depth)
        func container(_ open: String, _ close: String, _ items: [String]) -> String {
            guard !items.isEmpty else { return open + close }
            return pretty ? open + "\n" + indent + "  " + items.joined(separator: ",\n" + indent + "  ") + "\n" + indent + close
                : open + items.joined(separator: ",") + close
        }
        switch self {
        case .null: return "null"
        case .bool(let value): return String(value)
        case .number(let value):
            if !omitNulls { return value }
            return Self.numberString(value)
        case .string(let value): return quote(value)
        case .array(let values):
            return container("[", "]", values.map { $0.json(pretty: pretty, omitNulls: omitNulls, depth: depth + 1) })
        case .object(let entries):
            return container("{", "}", entries.compactMap { key, value in
                if omitNulls, case .null = value { return nil }
                return quote(key) + (pretty ? ": " : ":") + value.json(pretty: pretty, omitNulls: omitNulls, depth: depth + 1)
            })
        }
    }
}

private struct OptionJSONParser {
    private let chars: [Unicode.Scalar]
    private let strict: Bool
    private var index = 0

    init(_ text: String, strict: Bool) {
        chars = Array(text.unicodeScalars)
        self.strict = strict
    }

    mutating func parse() throws -> OptionJSON {
        if chars.first == "\u{feff}" { index += 1 }
        try whitespace()
        if !strict, String(String.UnicodeScalarView(chars.dropFirst(index).prefix(5))) == ")]}'\n" { index += 5 }
        let result = try value(depth: 0)
        try whitespace()
        guard index == chars.count else { throw UrlOptions.OptionError.invalidJSON }
        return result
    }

    private mutating func whitespace() throws {
        while index < chars.count {
            if isWhitespace(chars[index]) { index += 1; continue }
            if !strict && chars[index] == "#" {
                while index < chars.count && !["\n", "\r"].contains(chars[index]) { index += 1 }
                continue
            }
            if !strict && index + 1 < chars.count && chars[index] == "/" {
                if chars[index + 1] == "/" {
                    index += 2
                    while index < chars.count && !["\n", "\r"].contains(chars[index]) { index += 1 }
                    continue
                }
                if chars[index + 1] == "*" {
                    index += 2
                    while index + 1 < chars.count && !(chars[index] == "*" && chars[index + 1] == "/") { index += 1 }
                    guard index + 1 < chars.count else { throw UrlOptions.OptionError.invalidJSON }
                    index += 2
                    continue
                }
            }
            break
        }
    }

    private mutating func take(_ char: Unicode.Scalar) -> Bool {
        guard index < chars.count && chars[index] == char else { return false }
        index += 1
        return true
    }

    private mutating func value(depth: Int) throws -> OptionJSON {
        guard depth < 256 else { throw UrlOptions.OptionError.invalidJSON }
        try whitespace()
        guard index < chars.count else { throw UrlOptions.OptionError.invalidJSON }
        if take("{") {
            var entries: [(String, OptionJSON)] = []
            try whitespace()
            if take("}") { return .object(entries) }
            while true {
                try whitespace()
                let key = try tokenString()
                try whitespace()
                if !take(":") {
                    guard !strict && take("=") else { throw UrlOptions.OptionError.invalidJSON }
                    _ = take(">")
                }
                let entry = try value(depth: depth + 1)
                if depth > 0, let existing = entries.firstIndex(where: { $0.0 == key }) { entries[existing].1 = entry }
                else { entries.append((key, entry)) }
                try whitespace()
                if take("}") { return .object(entries) }
                guard take(",") || (!strict && take(";")) else { throw UrlOptions.OptionError.invalidJSON }
            }
        }
        if take("[") {
            var values: [OptionJSON] = []
            try whitespace()
            if take("]") { return .array(values) }
            while true {
                try whitespace()
                if !strict, index < chars.count, ",;]".unicodeScalars.contains(chars[index]) { values.append(.null) }
                else { values.append(try value(depth: depth + 1)) }
                try whitespace()
                if take("]") { return .array(values) }
                guard take(",") || (!strict && take(";")) else { throw UrlOptions.OptionError.invalidJSON }
            }
        }
        if chars[index] == "\"" || (!strict && chars[index] == "'") { return .string(try tokenString()) }
        let token = try unquoted()
        switch strict ? token : token.lowercased() {
        case "null": return .null
        case "true": return .bool(true)
        case "false": return .bool(false)
        default:
            if token.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil {
                return .number(token)
            }
            guard !strict else { throw UrlOptions.OptionError.invalidJSON }
            return .string(token)
        }
    }

    private mutating func unquoted() throws -> String {
        let start = index
        while index < chars.count && !isWhitespace(chars[index]) && !"{}[]:,;=#/\\".unicodeScalars.contains(chars[index]) { index += 1 }
        guard start != index else { throw UrlOptions.OptionError.invalidJSON }
        return String(String.UnicodeScalarView(chars[start..<index]))
    }

    private func isWhitespace(_ char: Unicode.Scalar) -> Bool {
        [" ", "\t", "\r", "\n"].contains(char)
    }

    private mutating func tokenString() throws -> String {
        guard index < chars.count else { throw UrlOptions.OptionError.invalidJSON }
        let quote = chars[index]
        guard quote == "\"" || (!strict && quote == "'") else {
            guard !strict else { throw UrlOptions.OptionError.invalidJSON }
            return try unquoted()
        }
        index += 1
        var units: [UInt16] = []
        while index < chars.count {
            let char = chars[index]
            index += 1
            if char == quote { return String(decoding: units, as: UTF16.self) }
            if char == "\\" {
                guard index < chars.count else { throw UrlOptions.OptionError.invalidJSON }
                let escape = chars[index]
                index += 1
                switch escape {
                case "u":
                    guard index + 4 <= chars.count,
                          let unit = UInt16(String(String.UnicodeScalarView(chars[index..<index + 4])), radix: 16) else { throw UrlOptions.OptionError.invalidJSON }
                    units.append(unit)
                    index += 4
                case "b": units.append(8)
                case "f": units.append(12)
                case "n": units.append(10)
                case "r": units.append(13)
                case "t": units.append(9)
                case "\"", "\\", "/": units.append(contentsOf: String(escape).utf16)
                case "'" where !strict, "\n" where !strict, "\r" where !strict:
                    units.append(contentsOf: String(escape).utf16)
                default: throw UrlOptions.OptionError.invalidJSON
                }
            } else {
                if strict && char.value < 32 { throw UrlOptions.OptionError.invalidJSON }
                units.append(contentsOf: String(char).utf16)
            }
        }
        throw UrlOptions.OptionError.invalidJSON
    }
}
