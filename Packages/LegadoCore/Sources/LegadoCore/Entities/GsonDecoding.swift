import Foundation

/// 为动态 Kotlin 默认值提供毫秒时钟。
public enum GsonDecoding {
    public static func currentTimeMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    static let treeKey = CodingUserInfoKey(rawValue: "LegadoCore.Gson.tree")!
    static let timeKey = CodingUserInfoKey(rawValue: "LegadoCore.Gson.time")!
    static let ruleStringKey = CodingUserInfoKey(rawValue: "LegadoCore.Gson.ruleString")!

    static func time(from decoder: Decoder) -> Int64 {
        decoder.userInfo[timeKey] as? Int64 ?? currentTimeMillis()
    }
}

/// 导入应使用此入口：Foundation 的 Decoder 协议本身不暴露数字原始字面量。
/// 此入口保留 12.0、1e+02 等 Gson String 转换所需的原始形式。
public struct GsonJSONDecoder {
    private let now: () -> Int64

    public init(now: @escaping () -> Int64 = GsonDecoding.currentTimeMillis) {
        self.now = now
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decode(type, from: data, ruleString: false)
    }

    func decodeRuleString<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decode(type, from: data, ruleString: true)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, ruleString: Bool) throws -> T {
        let tree = try GsonValue.parse(data)
        let decoder = JSONDecoder()
        decoder.userInfo[GsonDecoding.treeKey] = tree
        decoder.userInfo[GsonDecoding.timeKey] = now()
        decoder.userInfo[GsonDecoding.ruleStringKey] = ruleString
        return try decoder.decode(type, from: data)
    }
}

protocol GsonRule: Decodable {}

extension KeyedDecodingContainer {
    private func value(forKey key: Key) throws -> GsonValue? {
        try decodeIfPresent(GsonValue.self, forKey: key)
    }

    func gsonString(forKey key: Key) throws -> String? {
        try value(forKey: key)?.stringValue
    }

    func gsonInt(forKey key: Key) throws -> Int? {
        guard case let .number(raw)? = try value(forKey: key) else { return nil }
        return Int(Int32(truncatingIfNeeded: GsonValue.integerBits(raw)))
    }

    func gsonLong(forKey key: Key) throws -> Int64? {
        guard let value = try value(forKey: key) else { return nil }
        return try value.readerLong(codingPath: codingPath + [key])
    }

    func gsonBoxedInt(forKey key: Key, tree: Bool = false) throws -> Int? {
        guard let value = try value(forKey: key) else { return nil }
        if tree {
            switch value {
            case let .number(raw): return Int(Int32(truncatingIfNeeded: GsonValue.integerBits(raw)))
            case let .string(raw):
                if let result = Int32(raw) { return Int(result) }
            default: break
            }
        } else if let raw = value.numericText {
            if let result = Int32(raw) { return Int(result) }
            if let number = Double(raw), let result = Int32(exactly: number) { return Int(result) }
        }
        throw DecodingError.typeMismatch(Int.self, .init(codingPath: codingPath + [key], debugDescription: "Integer 字段需要可表示的整数"))
    }

    func gsonFloat(forKey key: Key) throws -> Float? {
        guard let value = try value(forKey: key) else { return nil }
        guard let raw = value.numericText, let result = Float(raw) else {
            throw DecodingError.typeMismatch(Float.self, .init(codingPath: codingPath + [key], debugDescription: "Float 字段需要数字或数字字符串"))
        }
        return result
    }

    func gsonLongList(forKey key: Key) throws -> [Int64?]? {
        guard let value = try value(forKey: key) else { return nil }
        guard case let .array(items) = value else {
            throw DecodingError.typeMismatch([Int64?].self, .init(codingPath: codingPath + [key], debugDescription: "需要 Long 数组"))
        }
        return try items.map {
            if case .null = $0 { return nil }
            return try $0.readerLong(codingPath: codingPath + [key])
        }
    }

    func gsonBool(forKey key: Key) throws -> Bool? {
        guard let value = try value(forKey: key) else { return nil }
        switch value {
        case let .bool(value): return value
        case let .string(value): return value.lowercased() == "true"
        default:
            throw DecodingError.typeMismatch(Bool.self, .init(codingPath: codingPath + [key], debugDescription: "Boolean 字段需要布尔值或字符串"))
        }
    }

    func gsonRule<T: GsonRule>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard let value = try value(forKey: key) else { return nil }
        switch value {
        case .array: return nil
        case let .string(text):
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            let tree = try GsonValue.parse(Data(text.utf8))
            if case .null = tree { return nil }
            guard case .object = tree else {
                throw DecodingError.typeMismatch(type, .init(codingPath: codingPath + [key], debugDescription: "规则字符串必须包含对象或 null"))
            }
            return try GsonJSONDecoder().decodeRuleString(type, from: Data(text.utf8))
        case .object: return try decode(type, forKey: key)
        default:
            throw DecodingError.typeMismatch(type, .init(codingPath: codingPath + [key], debugDescription: "规则必须为对象或 JSON 字符串"))
        }
    }
}

indirect enum GsonValue: Decodable {
    case null
    case bool(Bool)
    case string(String)
    case number(String)
    case array([GsonValue])
    case object([(String, GsonValue)])

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        if let tree = decoder.userInfo[GsonDecoding.treeKey] as? GsonValue,
           let value = tree.at(decoder.codingPath[...]) {
            self = value
            return
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Int64.self) { self = .number(String(value)) }
        else if let value = try? container.decode(Double.self) { self = .number(String(value)) }
        else if let value = try? container.decode([GsonValue].self) { self = .array(value) }
        else {
            let object = try decoder.container(keyedBy: Key.self)
            self = .object(try object.allKeys.map { ($0.stringValue, try object.decode(GsonValue.self, forKey: $0)) })
        }
    }

    private func at(_ path: ArraySlice<CodingKey>) -> GsonValue? {
        guard let key = path.first else { return self }
        switch self {
        case let .object(fields): return fields.last(where: { $0.0 == key.stringValue })?.1.at(path.dropFirst())
        case let .array(values):
            guard let index = key.intValue, values.indices.contains(index) else { return nil }
            return values[index].at(path.dropFirst())
        default: return nil
        }
    }

    subscript(_ key: String) -> GsonValue? {
        guard case let .object(fields) = self else { return nil }
        return fields.last(where: { $0.0 == key })?.1
    }

    var numericText: String? {
        switch self {
        case let .number(raw), let .string(raw): return raw
        default: return nil
        }
    }

    func readerLong(codingPath: [CodingKey]) throws -> Int64 {
        if let raw = numericText {
            if let integer = Int64(raw) { return integer }
            if let number = Double(raw), number.isFinite {
                // JsonReader.nextLong 先转 Double，再按 Java long 强制转换并检查相等。
                let result: Int64
                if number >= Double(Int64.max) { result = .max }
                else if number <= Double(Int64.min) { result = .min }
                else { result = Int64(number) }
                if Double(result) == number { return result }
            }
        }
        throw DecodingError.typeMismatch(Int64.self, .init(codingPath: codingPath, debugDescription: "Long 字段需要可表示的整数"))
    }

    var mappedLong: Int64? {
        switch self {
        case let .number(raw): return Int64(bitPattern: Self.integerBits(raw))
        case let .string(raw): return Int64(raw)
        default: return nil
        }
    }

    var mappedInt: Int? {
        switch self {
        case let .number(raw): return Int(Int32(truncatingIfNeeded: Self.integerBits(raw)))
        case let .string(raw): return Int32(raw).map(Int.init)
        default: return nil
        }
    }

    var stringValue: String? {
        switch self {
        case .null: return nil
        case let .string(value), let .number(value): return value
        case let .bool(value): return value ? "true" : "false"
        default: return json
        }
    }

    var json: String {
        switch self {
        case .null: return "null"
        case let .bool(value): return value ? "true" : "false"
        case let .number(value): return value
        case let .string(value):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            return String(decoding: try! encoder.encode(value), as: UTF8.self)
        case let .array(values): return "[" + values.map(\.json).joined(separator: ",") + "]"
        case let .object(fields):
            return "{" + fields.map { GsonValue.string($0.0).json + ":" + $0.1.json }.joined(separator: ",") + "}"
        }
    }

    // BigDecimal.toBigInteger().longValue() 的截断和低 64 位语义，避免 Double 精度损失。
    static func integerBits(_ raw: String) -> UInt64 {
        let negative = raw.hasPrefix("-")
        let unsigned = negative ? String(raw.dropFirst()) : raw
        let parts = unsigned.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        let mantissa = String(parts[0])
        let exponent: Int
        if parts.count == 1 { exponent = 0 }
        else { exponent = Int(parts[1]) ?? (parts[1].hasPrefix("-") ? -100000 : 100000) }
        let fraction = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        let digits = mantissa.filter { $0 != "." }
        let fractionalCount = fraction.count == 2 ? fraction[1].count : 0
        let shift = max(-100000, min(100000, exponent)) - fractionalCount
        let kept = shift < 0 ? String(digits.prefix(max(0, digits.count + shift))) : digits
        var bits: UInt64 = 0
        for byte in kept.utf8 { bits = bits &* 10 &+ UInt64(byte - 48) }
        if shift >= 64 { bits = 0 }
        else if shift > 0 { for _ in 0..<shift { bits = bits &* 10 } }
        return negative ? 0 &- bits : bits
    }

    static func parse(_ data: Data) throws -> GsonValue {
        // Foundation 验证结构；下面的词法读取只保留它不公开的数字字面量和对象顺序。
        _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let tokens = tokenizeValidatedJSON(data)
        var index = 0
        func take() throws -> String {
            guard index < tokens.count else { throw corrupt() }
            defer { index += 1 }
            return tokens[index]
        }
        func corrupt() -> DecodingError {
            .dataCorrupted(.init(codingPath: [], debugDescription: "无效 JSON"))
        }
        func read() throws -> GsonValue {
            let token = try take()
            switch token {
            case "null": return .null
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "[":
                var values: [GsonValue] = []
                if tokens[index] == "]" { index += 1; return .array(values) }
                while true {
                    values.append(try read())
                    let next = try take()
                    if next == "]" { return .array(values) }
                    guard next == "," else { throw corrupt() }
                }
            case "{":
                var fields: [(String, GsonValue)] = []
                if tokens[index] == "}" { index += 1; return .object(fields) }
                while true {
                    let key = try JSONDecoder().decode(String.self, from: Data(try take().utf8))
                    guard try take() == ":" else { throw corrupt() }
                    let value = try read()
                    if let existing = fields.firstIndex(where: { $0.0 == key }) { fields[existing].1 = value }
                    else { fields.append((key, value)) }
                    let next = try take()
                    if next == "}" { return .object(fields) }
                    guard next == "," else { throw corrupt() }
                }
            default:
                if token.hasPrefix("\"") {
                    return .string(try JSONDecoder().decode(String.self, from: Data(token.utf8)))
                }
                return .number(token)
            }
        }
        let value = try read()
        guard index == tokens.count else { throw corrupt() }
        return value
    }

    // 输入已由 Foundation 验证；逐字节扫描避免长字符串耗尽 ICU 正则的匹配栈。
    private static func tokenizeValidatedJSON(_ data: Data) -> [String] {
        let bytes = Array(data)
        var offset = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        var tokens: [String] = []
        while offset < bytes.count {
            let start = offset
            switch bytes[offset] {
            case 9, 10, 13, 32:
                offset += 1
                continue
            case 34:
                offset += 1
                while offset < bytes.count {
                    let byte = bytes[offset]
                    offset += 1
                    if byte == 92 { offset += 1 }
                    else if byte == 34 { break }
                }
            case 91, 93, 123, 125, 44, 58:
                offset += 1
            default:
                scanPrimitive: while offset < bytes.count {
                    switch bytes[offset] {
                    case 9, 10, 13, 32, 91, 93, 123, 125, 44, 58:
                        break scanPrimitive
                    default:
                        offset += 1
                    }
                }
            }
            tokens.append(String(decoding: bytes[start..<offset], as: UTF8.self))
        }
        return tokens
    }
}
