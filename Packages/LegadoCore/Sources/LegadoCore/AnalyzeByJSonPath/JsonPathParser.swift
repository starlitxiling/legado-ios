import Foundation

public enum JsonPathError: Error, Equatable {
    case invalidPath(String)
    case pathNotFound
    case invalidFunction(String)
}

indirect enum JsonPathStep {
    case property([String]), wildcard, indices([Int]), slice(Int?, Int?, Int)
    case recursive(JsonPathStepBox), filter(JsonPathPredicate), function(String)

    func indefinite(isLeaf: Bool) -> Bool {
        switch self {
        case .wildcard, .slice, .recursive, .filter: return true
        case .indices(let indices): return indices.count > 1
        case .property(let keys): return keys.count > 1 && !isLeaf
        default: return false
        }
    }
}

struct JsonPathStepBox { let step: JsonPathStep }

struct JsonPathParser {
    private var chars: [Character]
    private var position = 0

    init(_ source: String) {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        chars = Array(source.isEmpty || source.hasPrefix("$") || source.hasPrefix("@") ? source : "$." + source)
    }

    mutating func parse() throws -> [JsonPathStep] {
        guard chars.first == "$" || chars.first == "@" else { throw invalid() }
        position = 1
        var steps: [JsonPathStep] = []
        while position < chars.count {
            if chars[position] == "[" { steps.append(try bracket()); continue }
            guard chars[position] == "." else { throw invalid() }
            position += 1
            var recursive = false
            if position < chars.count, chars[position] == "." { recursive = true; position += 1 }
            guard position < chars.count else { throw invalid() }
            let step: JsonPathStep
            if chars[position] == "[" { step = try bracket() }
            else if chars[position] == "*" { position += 1; step = .wildcard }
            else {
                let start = position
                while position < chars.count, !".[]() \t\r\n".contains(chars[position]) { position += 1 }
                guard position > start else { throw invalid() }
                let name = String(chars[start..<position])
                if position < chars.count, chars[position] == "(" {
                    guard position + 1 < chars.count, chars[position + 1] == ")" else { throw invalid() }
                    position += 2
                    step = .function(name)
                } else { step = .property([name]) }
            }
            steps.append(recursive ? .recursive(JsonPathStepBox(step: step)) : step)
        }
        return steps
    }

    private mutating func bracket() throws -> JsonPathStep {
        let start = position
        let text = try Self.balanced(chars, position: &position)
        let body = text.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        if body == "*" { return .wildcard }
        if body.hasPrefix("?(") && body.hasSuffix(")") {
            var parser = try JsonPathPredicateParser(String(body.dropFirst(2).dropLast()))
            return .filter(try parser.parse())
        }
        if body.first == "'" || body.first == "\"" {
            var scanner = try JsonPathPredicateParser(body)
            return .property(try scanner.propertyNames())
        }
        if body.contains(":") {
            let parts = body.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard (2...3).contains(parts.count), parts.allSatisfy({ $0.isEmpty || Int($0) != nil }) else { throw invalid() }
            let step = parts.count == 3 ? Int(parts[2]) ?? 1 : 1
            guard step != 0 else { throw invalid() }
            return .slice(Int(parts[0]), Int(parts[1]), step)
        }
        let parts = body.split(separator: ",", omittingEmptySubsequences: false)
        let indices = parts.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !indices.isEmpty, indices.count == parts.count else {
            throw JsonPathError.invalidPath(String(chars[start..<position]))
        }
        return .indices(indices)
    }

    private func invalid() -> JsonPathError { .invalidPath(String(chars)) }

    static func balanced(_ chars: [Character], position: inout Int) throws -> String {
        let start = position
        var stack: [Character] = []
        var quote: Character?
        var escaped = false
        while position < chars.count {
            let char = chars[position]
            position += 1
            if let current = quote {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == current { quote = nil }
                continue
            }
            if char == "'" || char == "\"" || char == "/" { quote = char; continue }
            if char == "[" { stack.append("]") }
            else if char == "(" { stack.append(")") }
            else if char == "]" || char == ")" {
                guard stack.popLast() == char else { throw JsonPathError.invalidPath(String(chars)) }
                if stack.isEmpty { return String(chars[start..<position]) }
            }
        }
        throw JsonPathError.invalidPath(String(chars))
    }
}
