import Foundation

/// NSDictionary 桥接保留既有对象接口；键枚举遵循 JsonSmartJsonProvider 的插入顺序。
final class JsonPathObject: NSDictionary {
    let orderedKeys: [String]
    private let values: [String: Any]

    init(_ entries: [(String, Any)]) {
        var keys: [String] = [], values: [String: Any] = [:]
        for (key, value) in entries {
            if values[key] == nil { keys.append(key) }
            values[key] = value
        }
        orderedKeys = keys
        self.values = values
        super.init()
    }

    override var count: Int { values.count }
    override func keyEnumerator() -> NSEnumerator { (orderedKeys as NSArray).objectEnumerator() }
    override func object(forKey aKey: Any) -> Any? { (aKey as? String).flatMap { values[$0] } }
    required init?(coder: NSCoder) { return nil }
    override convenience init() { self.init([]) }
    override convenience init(objects: UnsafePointer<AnyObject>?, forKeys keys: UnsafePointer<NSCopying>?, count: Int) {
        var entries: [(String, Any)] = []
        if let objects, let keys {
            for index in 0..<count {
                if let key = keys[index] as? String { entries.append((key, objects[index])) }
            }
        }
        self.init(entries)
    }
}

struct JsonPathJSONParser {
    private let bytes: [UInt8]
    private var position = 0

    init(_ text: String) { bytes = Array(text.utf8) }

    mutating func parse() throws -> Any {
        let result = try value()
        whitespace()
        guard position == bytes.count else { throw invalid() }
        return result
    }

    private mutating func value() throws -> Any {
        whitespace()
        guard position < bytes.count else { throw invalid() }
        switch bytes[position] {
        case 123:
            position += 1
            var entries: [(String, Any)] = []
            if consume(125) { return JsonPathObject(entries) }
            repeat {
                whitespace()
                let key = try string()
                guard consume(58) else { throw invalid() }
                entries.append((key, try value()))
            } while consume(44)
            guard consume(125) else { throw invalid() }
            return JsonPathObject(entries)
        case 91:
            position += 1
            var elements: [Any] = []
            if consume(93) { return elements }
            repeat { elements.append(try value()) } while consume(44)
            guard consume(93) else { throw invalid() }
            return elements
        case 34: return try string()
        case 116: try literal("true"); return true
        case 102: try literal("false"); return false
        case 110: try literal("null"); return NSNull()
        default: return try number()
        }
    }

    private mutating func string() throws -> String {
        guard position < bytes.count, bytes[position] == 34 else { throw invalid() }
        let start = position
        position += 1
        var escaped = false
        while position < bytes.count {
            let byte = bytes[position]
            position += 1
            if escaped { escaped = false }
            else if byte == 92 { escaped = true }
            else if byte == 34 {
                return try JSONDecoder().decode(String.self, from: Data(bytes[start..<position]))
            }
        }
        throw invalid()
    }

    private mutating func number() throws -> Any {
        let start = position
        if position < bytes.count, bytes[position] == 45 { position += 1 }
        guard position < bytes.count else { throw invalid() }
        if bytes[position] == 48 { position += 1 }
        else {
            guard (49...57).contains(bytes[position]) else { throw invalid() }
            digits()
        }
        var floating = false
        if position < bytes.count, bytes[position] == 46 {
            floating = true
            position += 1
            let start = position
            digits()
            guard position > start else { throw invalid() }
        }
        if position < bytes.count, bytes[position] == 101 || bytes[position] == 69 {
            floating = true
            position += 1
            if position < bytes.count, bytes[position] == 43 || bytes[position] == 45 { position += 1 }
            let start = position
            digits()
            guard position > start else { throw invalid() }
        }
        let text = String(decoding: bytes[start..<position], as: UTF8.self)
        if !floating, let integer = Int64(text) { return NSNumber(value: integer) }
        guard let double = Double(text), double.isFinite else { throw invalid() }
        return NSNumber(value: double)
    }

    private mutating func digits() {
        while position < bytes.count, (48...57).contains(bytes[position]) { position += 1 }
    }

    private mutating func literal(_ text: String) throws {
        let literal = Array(text.utf8)
        guard bytes.count - position >= literal.count,
              Array(bytes[position..<(position + literal.count)]) == literal else { throw invalid() }
        position += literal.count
    }

    private mutating func whitespace() {
        while position < bytes.count, [9, 10, 13, 32].contains(bytes[position]) { position += 1 }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard position < bytes.count, bytes[position] == byte else { return false }
        position += 1
        return true
    }

    private func invalid() -> JsonPathError { .invalidPath("JSON byte \(position)") }
}
