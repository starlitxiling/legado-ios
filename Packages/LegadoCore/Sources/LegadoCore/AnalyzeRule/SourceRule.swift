import Foundation

/// 规格 §2.4、§7.3：段编译参数保留字面量、变量、内插和捕获组。
public enum RuleParameter: Equatable {
    case literal(String), get(String), expression(String), capture(Int, String)
}

/// 规格 §2、§8.3：缓存词法段，保留 Kotlin 的可变替换字段。
public final class SourceRule {
    /// 规格 §2.2、§2.4：前缀与模板分析后的模式。
    public private(set) var mode: RuleMode
    /// 规格 §2.3、§7.1：初始化时为剥离后的文本，求值后为回填并拆分的规则。
    public private(set) var rule: String
    /// 规格 §2.3：每次求值前执行的变量子规则。
    public private(set) var putMap: [String: String] = [:]
    /// 规格 §2.4：按文本顺序记录的编译参数。
    public private(set) var parameters: [RuleParameter] = []
    private var replacementState: RuleReplacement?

    /// 规格 §2.2–§2.4：识别前缀，剥离变量写入并编译模板。
    public init(_ text: String, mode: RuleMode = .default, isJSON: Bool = false) throws {
        self.mode = mode
        rule = text
        let lower = text.lowercased()
        if mode != .js && mode != .regex {
            if lower.hasPrefix("@css:") { self.mode = .default }
            else if text.hasPrefix("@@") { self.mode = .default; rule = String(text.dropFirst(2)) }
            else if lower.hasPrefix("@xpath:") { self.mode = .xpath; rule = String(text.dropFirst(7)) }
            else if lower.hasPrefix("@json:") { self.mode = .json; rule = String(text.dropFirst(6)) }
            else if isJSON || text.hasPrefix("$.") || text.hasPrefix("$[") { self.mode = .json }
            else if text.hasPrefix("/") { self.mode = .xpath }
        }
        let put = try NSRegularExpression(pattern: #"@put:(\{[^}]+?\})"#, options: .caseInsensitive)
        let original = rule as NSString
        let matches = put.matches(in: rule, range: NSRange(location: 0, length: original.length))
        for match in matches {
            let json = original.substring(with: match.range(at: 1))
            if let values = PutObject.decode(json) { putMap.merge(values) { _, new in new } }
        }
        rule = put.stringByReplacingMatches(in: rule, range: NSRange(location: 0, length: original.length), withTemplate: "")
        let eval = try NSRegularExpression(pattern: #"@get:\{[^}]+?\}|\{\{[\w\W]*?\}\}"#, options: .caseInsensitive)
        let source = rule as NSString
        let evaluations = eval.matches(in: rule, range: NSRange(location: 0, length: source.length))
        if let first = evaluations.first, self.mode != .js && self.mode != .regex,
           !source.substring(to: first.range.location).contains("##") { self.mode = .regex }
        var cursor = 0
        for match in evaluations {
            try splitCaptures(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            let token = source.substring(with: match.range)
            if token.lowercased().hasPrefix("@get:") { parameters.append(.get(String(token.dropFirst(6).dropLast()))) }
            else { parameters.append(.expression(String(token.dropFirst(2).dropLast(2)))) }
            cursor = NSMaxRange(match.range)
        }
        try splitCaptures(source.substring(from: cursor))
    }

    /// 规格 §7.3：逆序执行参数，拼接保持原顺序；内嵌规则由整个内容求值。
    public func makeUpRule(_ result: Any?, context: AnalyzeRule) throws -> RuleReplacement {
        var fragments: [String] = []
        for parameter in parameters.reversed() {
            switch parameter {
            case .literal(let value): fragments.append(value)
            case .get(let key): fragments.append(context.get(key))
            case .capture(let index, let literal):
                if let values = JsEngine.nativeValue(result) as? [Any] { fragments.append(index < values.count && !(values[index] is NSNull) ? ruleText(values[index]) : "") }
                else { fragments.append(literal) }
            case .expression(let expression):
                if expression.hasPrefix("@") || expression.hasPrefix("$.") || expression.hasPrefix("$[") || expression.hasPrefix("//") {
                    fragments.append(try context.evaluateEmbeddedRule(expression))
                } else {
                    let value = try context.evaluateScript(expression, result: result)
                    if let number = integralScriptNumber(value) {
                        fragments.append(String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), number))
                    } else if let value, !(value is NSNull) { fragments.append(ruleText(value)) }
                    else { fragments.append("") }
                }
            }
        }
        let compiled = RuleReplacement(parameters.isEmpty ? rule : fragments.reversed().joined(), retaining: replacementState)
        rule = compiled.rule
        replacementState = compiled
        return compiled
    }

    private func splitCaptures(_ text: String) throws {
        let prefix = text.components(separatedBy: "##")[0]
        let regex = try NSRegularExpression(pattern: #"\$\d{1,2}"#)
        let source = text as NSString
        let matches = regex.matches(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length))
        if !matches.isEmpty, mode != .js && mode != .regex { mode = .regex }
        var cursor = 0
        for match in matches {
            if match.range.location > cursor { parameters.append(.literal(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))) }
            let token = source.substring(with: match.range)
            let index = Int(token.dropFirst()) ?? 0
            parameters.append(index == 0 ? .literal(token) : .capture(index, token))
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length { parameters.append(.literal(source.substring(from: cursor))) }
    }
}

// @put 的词法边界已禁止嵌套右花括号，仅接受标量值。
private struct PutObject {
    static func decode(_ text: String) -> [String: String]? {
        if let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
            var result: [String: String] = [:]
            for (key, value) in object {
                guard value is String || value is NSNumber || value is NSNull else { return nil }
                result[key] = value is NSNull ? "" : ruleText(value)
            }
            return result
        }
        var parser = PutObject(chars: Array(text))
        return parser.object()
    }

    let chars: [Character]
    var index = 0

    mutating func whitespace() {
        while index < chars.count, chars[index].isWhitespace { index += 1 }
    }

    mutating func token() -> String? {
        whitespace()
        guard index < chars.count else { return nil }
        let quote = chars[index]
        if quote == "\"" || quote == "'" {
            index += 1
            var text = ""
            while index < chars.count {
                let char = chars[index]; index += 1
                if char == quote { return text }
                if char == "\\" {
                    guard index < chars.count else { return nil }
                    let next = chars[index]; index += 1
                    switch next {
                    case "n": text.append("\n")
                    case "r": text.append("\r")
                    case "t": text.append("\t")
                    case "b": text.append("\u{8}")
                    case "f": text.append("\u{c}")
                    case "u":
                        guard index + 4 <= chars.count, let code = UInt32(String(chars[index..<index + 4]), radix: 16), let scalar = Unicode.Scalar(code) else { return nil }
                        text.unicodeScalars.append(scalar); index += 4
                    case "\\", "'", "\"", "/": text.append(next)
                    default: return nil
                    }
                } else { text.append(char) }
            }
            return nil
        }
        let start = index
        while index < chars.count, !":=,;}[]".contains(chars[index]), !chars[index].isWhitespace { index += 1 }
        return index > start ? String(chars[start..<index]) : nil
    }

    mutating func object() -> [String: String]? {
        guard chars.first == "{" else { return nil }
        index = 1
        var values: [String: String] = [:]
        while true {
            whitespace()
            guard index < chars.count else { return nil }
            if chars[index] == "}" { index += 1; whitespace(); return index == chars.count ? values : nil }
            guard let key = token() else { return nil }
            whitespace()
            guard index < chars.count, chars[index] == ":" || chars[index] == "=" else { return nil }
            index += 1
            if index < chars.count, chars[index] == ">" { index += 1 }
            whitespace()
            let quoted = index < chars.count && (chars[index] == "'" || chars[index] == "\"")
            guard let value = token() else { return nil }
            values[key] = !quoted && value.lowercased() == "null" ? "" : value
            whitespace()
            guard index < chars.count else { return nil }
            if chars[index] == "," || chars[index] == ";" { index += 1 }
            else if chars[index] != "}" { return nil }
        }
    }
}
