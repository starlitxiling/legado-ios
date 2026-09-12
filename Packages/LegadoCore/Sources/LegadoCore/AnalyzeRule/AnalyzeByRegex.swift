import Foundation

/// 规格 §4：中间正则拼接组 0，最后正则返回捕获组。
public struct AnalyzeByRegex: SelectorEngine {
    /// 规格 §4：创建无状态的正则选择器。
    public init() {}

    /// 规格 §4：字符串入口返回模板文本，对象入口提取捕获组。
    public func evaluate(_ rule: String, content: Any, operation: RuleOperation, context: AnalyzeRule) throws -> Any? {
        switch operation {
        case .string, .stringList: return rule
        case .element: return try getElement(ruleText(content), rules: patterns(rule))
        case .elements: return try getElements(ruleText(content), rules: patterns(rule))
        }
    }

    /// 规格 §4；Kotlin AnalyzeByRegex.kt:20 的未匹配组强制非空断言会失败。
    public func getElement(_ content: String, rules: [String]) throws -> [String]? {
        try matches(content, rules: rules, first: true).first
    }

    /// 规格 §4：对象列表中的未匹配组为空串。
    public func getElements(_ content: String, rules: [String]) throws -> [[String]] {
        try matches(content, rules: rules, first: false)
    }

    private func patterns(_ rule: String) -> [String] {
        rule.components(separatedBy: "&&").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func matches(_ content: String, rules: [String], first: Bool) throws -> [[String]] {
        guard !rules.isEmpty else { throw RuleEvaluationError.emptyRegex }
        var text = content
        for (index, pattern) in rules.enumerated() {
            let regex = try NSRegularExpression(pattern: pattern)
            let source = text as NSString
            let range = NSRange(location: 0, length: source.length)
            let last = index == rules.count - 1
            let matches: [NSTextCheckingResult]
            if last && first { matches = regex.firstMatch(in: text, range: range).map { [$0] } ?? [] }
            else { matches = regex.matches(in: text, range: range) }
            guard !matches.isEmpty else { return [] }
            if last {
                return try matches.map { match in
                    try (0..<match.numberOfRanges).map { group in
                        let range = match.range(at: group)
                        if range.location == NSNotFound {
                            if first { throw RuleEvaluationError.unmatchedCapture(group) }
                            return ""
                        }
                        return source.substring(with: range)
                    }
                }
            }
            text = matches.map { source.substring(with: $0.range) }.joined()
        }
        return []
    }
}
