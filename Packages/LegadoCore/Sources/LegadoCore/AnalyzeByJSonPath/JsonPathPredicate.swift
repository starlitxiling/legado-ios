import Foundation
import CoreFoundation

indirect enum JsonPathPredicate {
    case literal(Any), path([JsonPathStep], Bool), regex(NSRegularExpression)
    case binary(String, JsonPathPredicate, JsonPathPredicate), not(JsonPathPredicate)

    func value(_ item: Any, root: Any) -> Any? {
        switch self {
        case .literal(let value): return value
        case .path(let steps, let absolute): return try? JsonPathEvaluator.read(steps, root: absolute ? root : item, document: root)
        case .regex(let regex): return regex
        case .not(let predicate): return !predicate.matches(item, root: root)
        case .binary(let op, let lhs, let rhs):
            if op == "&&" { return lhs.matches(item, root: root) && rhs.matches(item, root: root) }
            if op == "||" { return lhs.matches(item, root: root) || rhs.matches(item, root: root) }
            let left = lhs.value(item, root: root), right = rhs.value(item, root: root)
            switch op {
            case "==": return Self.equal(left, right)
            case "!=": return !Self.equal(left, right)
            case "in", "nin":
                guard let values = right as? [Any] else { return false }
                let found = values.contains { Self.equal(left, $0) }
                return op == "in" ? found : !found
            case "size":
                guard let count = Self.size(left), let number = Self.number(right) else { return false }
                return Double(count) == number
            case "empty":
                guard let count = Self.size(left), let bool = right as? NSNumber,
                      CFGetTypeID(bool) == CFBooleanGetTypeID() else { return false }
                return (count == 0) == bool.boolValue
            case "=~":
                guard let text = left as? String, let regex = right as? NSRegularExpression else { return false }
                let range = NSRange(text.startIndex..., in: text)
                return regex.firstMatch(in: text, range: range)?.range == range
            default:
                let order: ComparisonResult
                if let a = Self.number(left), let b = Self.number(right) {
                    order = a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
                } else if let a = left as? String, let b = right as? String { order = a.compare(b, options: .literal) }
                else { return false }
                switch op {
                case "<": return order == .orderedAscending
                case "<=": return order != .orderedDescending
                case ">": return order == .orderedDescending
                case ">=": return order != .orderedAscending
                default: return false
                }
            }
        }
    }

    func matches(_ item: Any, root: Any) -> Bool {
        if case .path = self { return value(item, root: root) != nil }
        return (value(item, root: root) as? Bool) == true
    }

    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value.doubleValue
    }

    private static func size(_ value: Any?) -> Int? {
        if let list = value as? [Any] { return list.count }
        if let string = value as? String { return string.utf16.count }
        return nil
    }

    private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        if lhs is NSNull || rhs is NSNull { return lhs is NSNull && rhs is NSNull }
        if let a = lhs as? NSNumber, let b = rhs as? NSNumber {
            guard (CFGetTypeID(a) == CFBooleanGetTypeID()) == (CFGetTypeID(b) == CFBooleanGetTypeID()) else { return false }
            return a == b
        }
        if let a = lhs as? String, let b = rhs as? String { return a == b }
        if let a = lhs as? [Any], let b = rhs as? [Any] {
            return a.count == b.count && zip(a, b).allSatisfy { equal($0, $1) }
        }
        if let a = lhs as? [String: Any], let b = rhs as? [String: Any] {
            return a.count == b.count && a.allSatisfy { equal($0.value, b[$0.key]) }
        }
        return false
    }
}

struct JsonPathPredicateParser {
    private var tokens: [String] = []
    private var position = 0

    init(_ text: String) throws {
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            if chars[index].isWhitespace { index += 1; continue }
            let start = index, char = chars[index]
            if char == "'" || char == "\"" || char == "/" {
                index += 1
                var escaped = false, closed = false
                while index < chars.count {
                    let next = chars[index]
                    index += 1
                    if escaped { escaped = false }
                    else if next == "\\" { escaped = true }
                    else if next == char { closed = true; break }
                }
                guard closed else { throw JsonPathError.invalidPath(text) }
                if char == "/" { while index < chars.count, chars[index].isLetter { index += 1 } }
            } else if char == "@" || char == "$" {
                index += 1
                while index < chars.count {
                    if chars[index] == "[" { _ = try JsonPathParser.balanced(chars, position: &index) }
                    else if chars[index].isWhitespace || "=!<>&|),".contains(chars[index]) { break }
                    else { index += 1 }
                }
            } else if "()[],".contains(char) { index += 1 }
            else if "=!<>&|".contains(char) {
                index += 1
                if index < chars.count, "=~&|".contains(chars[index]) { index += 1 }
            } else {
                while index < chars.count, !chars[index].isWhitespace, !"()[],=!<>&|".contains(chars[index]) { index += 1 }
            }
            guard index > start else { throw JsonPathError.invalidPath(text) }
            tokens.append(String(chars[start..<index]))
        }
    }

    mutating func parse() throws -> JsonPathPredicate {
        let result = try expression(0)
        guard position == tokens.count else { throw invalid() }
        return result
    }

    mutating func propertyNames() throws -> [String] {
        var names: [String] = []
        repeat {
            guard position < tokens.count else { throw invalid() }
            names.append(try string(tokens[position])); position += 1
        } while consume(",")
        guard position == tokens.count else { throw invalid() }
        return names
    }

    private mutating func expression(_ level: Int) throws -> JsonPathPredicate {
        if level == 3 { return try atom() }
        var left = try expression(level + 1)
        let operators = level == 0 ? ["||"] : level == 1 ? ["&&"] : ["==", "!=", "<", "<=", ">", ">=", "=~", "in", "nin", "size", "empty"]
        while position < tokens.count, operators.contains(tokens[position]) {
            let op = tokens[position]; position += 1
            left = .binary(op, left, try expression(level + 1))
        }
        return left
    }

    private mutating func atom() throws -> JsonPathPredicate {
        if consume("!") { return .not(try atom()) }
        if consume("(") {
            let result = try expression(0)
            guard consume(")") else { throw invalid() }
            return result
        }
        guard position < tokens.count else { throw invalid() }
        let token = tokens[position]; position += 1
        if token == "[" {
            var values: [Any] = []
            if consume("]") { return .literal(values) }
            repeat {
                guard case .literal(let value) = try atom() else { throw invalid() }
                values.append(value)
            } while consume(",")
            guard consume("]") else { throw invalid() }
            return .literal(values)
        }
        if token.first == "@" || token.first == "$" {
            var parser = JsonPathParser(token)
            return .path(try parser.parse(), token.first == "$")
        }
        if token.first == "'" || token.first == "\"" { return .literal(try string(token)) }
        if token.first == "/", let end = token.dropFirst().lastIndex(of: "/") {
            let flags = token[token.index(after: end)...]
            guard flags.allSatisfy({ "ims".contains($0) }) else { throw invalid() }
            var options: NSRegularExpression.Options = []
            if flags.contains("i") { options.insert(.caseInsensitive) }
            if flags.contains("m") { options.insert(.anchorsMatchLines) }
            if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }
            let pattern = String(token[token.index(after: token.startIndex)..<end]).replacingOccurrences(of: "\\/", with: "/")
            return .regex(try NSRegularExpression(pattern: pattern, options: options))
        }
        if token == "true" { return .literal(true) }
        if token == "false" { return .literal(false) }
        if token == "null" { return .literal(NSNull()) }
        if let value = Double(token), value.isFinite { return .literal(value) }
        throw invalid()
    }

    private mutating func consume(_ token: String) -> Bool {
        guard position < tokens.count, tokens[position] == token else { return false }
        position += 1
        return true
    }

    private func string(_ token: String) throws -> String {
        guard let quote = token.first, quote == "'" || quote == "\"", token.last == quote else { throw invalid() }
        var json = token
        if quote == "'" {
            json = "\""
            var escaped = false
            for char in token.dropFirst().dropLast() {
                if escaped {
                    json += char == "'" ? "'" : "\\" + String(char)
                    escaped = false
                } else if char == "\\" { escaped = true }
                else { json += char == "\"" ? "\\\"" : String(char) }
            }
            guard !escaped else { throw invalid() }
            json += "\""
        }
        guard let value = try JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed) as? String else { throw invalid() }
        return value
    }

    private func invalid() -> JsonPathError { .invalidPath(tokens.joined(separator: " ")) }
}
