import Foundation

/// 规格 §7：已回填规则的替换配置。
public struct RuleReplacement {
    /// 规格 §7.1：首段规则文本，已 trim。
    public let rule: String
    /// 规格 §7.1：第一个 ## 后的匹配表达式。
    public let pattern: String
    /// 规格 §7.1：第二个 ## 后的替换模板。
    public let replacement: String
    /// 规格 §7.1：超过三段时只提取首匹配。
    public let first: Bool

    /// 规格 §7.1；Kotlin AnalyzeRule.kt:826-834：空段覆盖旧值，缺失段保留旧值。
    public init(_ compiled: String, retaining previous: RuleReplacement? = nil) {
        let parts = compiled.components(separatedBy: "##")
        rule = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        pattern = parts.count > 1 ? parts[1] : previous?.pattern ?? ""
        replacement = parts.count > 2 ? parts[2] : previous?.replacement ?? ""
        first = parts.count > 3 || previous?.first == true
    }
}

/// 规格 §7.2：缓存至多 16 个合法正则；替换异常按 Kotlin 路径降级。
public final class RuleReplace {
    private var cache: [String: NSRegularExpression] = [:]
    /// 规格 §7.2：创建独立的替换正则缓存。
    public init() {}

    /// 规格 §7.2：执行替换，非法正则或模板按普通替换／首匹配规则降级。
    public func apply(_ text: String, replacement: RuleReplacement) -> String {
        guard !replacement.pattern.isEmpty else { return text }
        do {
            let regex: NSRegularExpression
            if let cached = cache[replacement.pattern] { regex = cached }
            else {
                regex = try NSRegularExpression(pattern: replacement.pattern)
                if cache.count < 16 { cache[replacement.pattern] = regex }
            }
            if replacement.first {
                guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return "" }
                let substring = (text as NSString).substring(with: match.range)
                return try replacing(substring, regex: regex, template: replacement.replacement, first: true)
            }
            return try replacing(text, regex: regex, template: replacement.replacement, first: false)
        } catch {
            return replacement.first ? replacement.replacement : text.replacingOccurrences(of: replacement.pattern, with: replacement.replacement)
        }
    }

    private func replacing(_ text: String, regex: NSRegularExpression, template: String, first: Bool) throws -> String {
        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        let matches = first ? regex.firstMatch(in: text, range: range).map { [$0] } ?? [] : regex.matches(in: text, range: range)
        var output = ""
        var cursor = 0
        for match in matches {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += try expand(template, match: match, source: source, regex: regex)
            cursor = NSMaxRange(match.range)
        }
        return output + source.substring(from: cursor)
    }

    private func expand(_ template: String, match: NSTextCheckingResult, source: NSString, regex: NSRegularExpression) throws -> String {
        let chars = Array(template)
        var index = 0
        var output = ""
        func digit(_ char: Character) -> Int? {
            guard char >= "0", char <= "9" else { return nil }
            return Int(String(char))
        }
        while index < chars.count {
            let char = chars[index]
            index += 1
            if char == "\\" {
                guard index < chars.count else { throw RuleEvaluationError.invalidReplacement }
                output.append(chars[index]); index += 1
            } else if char == "$" {
                guard index < chars.count else { throw RuleEvaluationError.invalidReplacement }
                let range: NSRange
                if chars[index] == "{" {
                    index += 1
                    let start = index
                    while index < chars.count, chars[index] != "}" { index += 1 }
                    guard index < chars.count, index > start else { throw RuleEvaluationError.invalidReplacement }
                    let name = String(chars[start..<index])
                    guard name.first?.isLetter == true, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw RuleEvaluationError.invalidReplacement }
                    // range(withName:) 对不存在的名称和未匹配组均返回 NSNotFound。
                    _ = try NSRegularExpression(pattern: "(?:" + regex.pattern + ")|\\k<" + name + ">")
                    range = match.range(withName: name)
                    index += 1
                } else {
                    guard var group = digit(chars[index]), group < match.numberOfRanges else { throw RuleEvaluationError.invalidReplacement }
                    index += 1
                    while index < chars.count, let next = digit(chars[index]), group * 10 + next < match.numberOfRanges {
                        group = group * 10 + next; index += 1
                    }
                    range = match.range(at: group)
                }
                if range.location != NSNotFound { output += source.substring(with: range) }
            } else { output.append(char) }
        }
        return output
    }
}
