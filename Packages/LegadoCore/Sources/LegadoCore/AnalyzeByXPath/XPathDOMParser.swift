import Foundation

indirect enum XPathDOMExpression {
    case literal(String), number(Double), function(String, [XPathDOMExpression])
    case binary(String, XPathDOMExpression, XPathDOMExpression), negative(XPathDOMExpression)
    case path(XPathDOMExpression?, Bool, [XPathDOMStep]), filter(XPathDOMExpression, [XPathDOMExpression])
}

struct XPathDOMStep {
    let axis: String
    let test: String
    var predicates: [XPathDOMExpression] = []
}

struct XPathDOMParser {
    private var tokens: [String] = []
    private var index = 0
    private var depth = 0
    private let rule: String

    init(_ rule: String) throws {
        self.rule = rule
        let chars = Array(rule)
        var i = 0
        while i < chars.count {
            if chars[i].isWhitespace { i += 1; continue }
            let start = i, character = chars[i]
            if character == "'" || character == "\"" {
                i += 1
                while i < chars.count, chars[i] != character { i += 1 }
                guard i < chars.count else { throw AnalyzeByXPath.EvaluationError.invalidXPath(rule) }
                i += 1
            } else if character.isNumber || character == "." && i + 1 < chars.count && chars[i + 1].isNumber {
                i += 1
                while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
            } else if character.isLetter || character == "_" {
                i += 1
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || "_-.".contains(chars[i]) || chars[i] == ":" && (i + 1 == chars.count || chars[i + 1] != ":") { i += 1 }
            } else {
                i += 1
                if i < chars.count, ["//", "..", "::", "!=", "<=", ">=", "^=", "*=", "$=", "~=", "!~"].contains(String(chars[start...i])) { i += 1 }
            }
            tokens.append(String(chars[start..<i]))
        }
    }

    mutating func parse() throws -> XPathDOMExpression {
        let result = try expression()
        guard index == tokens.count else { throw invalid() }
        return result
    }

    private mutating func expression(_ minimum: Int = 0) throws -> XPathDOMExpression {
        depth += 1
        defer { depth -= 1 }
        guard depth <= 128 else { throw invalid() }
        var lhs = try primary()
        let precedence = ["or": 1, "and": 2, "=": 3, "!=": 3, "^=": 3, "*=": 3, "$=": 3, "~=": 3, "!~": 3,
            "<": 4, "<=": 4, ">": 4, ">=": 4, "+": 5, "-": 5, "*": 6, "div": 6, "mod": 6, "|": 7]
        while index < tokens.count, let level = precedence[tokens[index]], level >= minimum {
            let operation = tokens[index]; index += 1
            lhs = .binary(operation, lhs, try expression(level + 1))
        }
        return lhs
    }

    private mutating func primary() throws -> XPathDOMExpression {
        guard index < tokens.count else { throw invalid() }
        if take("-") { return .negative(try primary()) }
        var result: XPathDOMExpression
        let token = tokens[index]
        if take("(") {
            result = try expression(); try require(")")
        } else if token.first == "'" || token.first == "\"" {
            index += 1; result = .literal(String(token.dropFirst().dropLast()))
        } else if let number = Double(token) {
            index += 1; result = .number(number)
        } else if token == "/" || token == "//" {
            index += 1
            var steps: [XPathDOMStep] = token == "//" ? [.init(axis: "descendant-or-self", test: "node()")] : []
            if index < tokens.count, !["|", ")", "]", ","].contains(tokens[index]) { steps.append(try step()) }
            result = .path(nil, true, steps)
        } else if index + 1 < tokens.count, tokens[index + 1] == "(" {
            index += 2
            var arguments: [XPathDOMExpression] = []
            if !take(")") {
                repeat { arguments.append(try expression()) } while take(",")
                try require(")")
            }
            result = .function(token, arguments)
        } else { result = .path(nil, false, [try step()]) }
        while index < tokens.count {
            if tokens[index] == "[" { result = .filter(result, try predicates()) }
            else if tokens[index] == "/" || tokens[index] == "//" {
                let recursive = tokens[index] == "//"; index += 1
                var steps: [XPathDOMStep] = recursive ? [.init(axis: "descendant-or-self", test: "node()")] : []
                steps.append(try step())
                result = .path(result, false, steps)
            } else { break }
        }
        return result
    }

    private mutating func step() throws -> XPathDOMStep {
        guard index < tokens.count else { throw invalid() }
        if take(".") { return .init(axis: "self", test: "node()") }
        if take("..") { return .init(axis: "parent", test: "node()") }
        var axis = take("@") ? "attribute" : "child"
        guard index < tokens.count else { throw invalid() }
        if index + 1 < tokens.count, tokens[index + 1] == "::" { axis = tokens[index]; index += 2 }
        guard ["child", "self", "parent", "attribute", "descendant", "descendant-or-self", "ancestor", "ancestor-or-self",
               "following", "preceding", "following-sibling", "preceding-sibling", "following-sibling-one", "preceding-sibling-one", "sibling"].contains(axis) else {
            throw AnalyzeByXPath.EvaluationError.unsupportedExtension(axis)
        }
        guard index < tokens.count else { throw invalid() }
        var name = tokens[index]; index += 1
        guard name == "*" || name.first?.isLetter == true || name.first == "_" else { throw invalid() }
        if take("(") { try require(")"); name += "()" }
        return XPathDOMStep(axis: axis, test: name, predicates: try predicates())
    }

    private mutating func predicates() throws -> [XPathDOMExpression] {
        var result: [XPathDOMExpression] = []
        while take("[") { result.append(try expression()); try require("]") }
        return result
    }
    private mutating func take(_ value: String) -> Bool {
        guard index < tokens.count, tokens[index] == value else { return false }
        index += 1; return true
    }
    private mutating func require(_ value: String) throws { if !take(value) { throw invalid() } }
    private func invalid() -> AnalyzeByXPath.EvaluationError { .invalidXPath(rule) }
}
