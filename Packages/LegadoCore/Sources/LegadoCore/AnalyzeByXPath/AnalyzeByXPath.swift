import Foundation
import Kanna
import SwiftSoup
import libxml2

/// 规格 §4、§6：XPath 1.0 求值；字符串组合交给 AnalyzeRule。
public final class AnalyzeByXPath: SelectorEngine {
    public enum EvaluationError: Error {
        case invalidXPath(String)
        case unsupportedExtension(String)
    }

    public init() {}

    /// AnalyzeByXPath.kt:52-103、133-141：保留节点列表，字符串结果逐项换行连接。
    public func evaluate(_ rule: String, content: Any, operation: RuleOperation, context: AnalyzeRule) throws -> Any? {
        if rule.isEmpty { return operation == .string ? nil : [Any]() }
        if operation == .element || operation == .elements {
            let analyzer = RuleAnalyzer(rule)
            let rules = try analyzer.splitRule(separators: ["&&", "||", "%%"])
            if rules.count > 1 {
                var lists: [[Any]] = []
                for part in rules {
                    let values = try evaluate(part, content: content, operation: operation, context: context) as? [Any] ?? []
                    if !values.isEmpty { lists.append(values) }
                    if !values.isEmpty && analyzer.elementsType == "||" { break }
                }
                if analyzer.elementsType == "%%", let first = lists.first {
                    return first.indices.flatMap { index in lists.compactMap { index < $0.count ? $0[index] : nil } }
                }
                return lists.flatMap { $0 }
            }
        }
        let projection = try XPathProjection(rule)
        let path = projection?.path ?? rule
        try validate(path)
        let inputs: [Any]
        if let elements = content as? SwiftSoup.Elements { inputs = elements.array() }
        else if let elements = content as? [Any] { inputs = elements }
        else { inputs = [content] }
        var results: [Any] = []
        for input in inputs {
            let document = try XPathDocument(input)
            switch document.root.xpath(path) {
            case .none: break
            case .NodeSet(let nodes):
                if let projection { results += try nodes.compactMap { try projection.value($0) } }
                else { results += nodes.map { XPathNode($0) } }
            case .Bool(let value): results.append(value ? "true" : "false")
            case .Number(let value): results.append(String(value))
            case .String(let value): results.append(value)
            }
        }
        switch operation {
        case .element, .elements: return results
        case .stringList: return results.map { ruleText($0) }
        case .string: return results.isEmpty ? nil : results.map { ruleText($0) }.joined(separator: "\n")
        }
    }

    private func validate(_ rule: String) throws {
        var quote: Character?
        let unquoted = String(rule.map { character -> Character in
            if let current = quote {
                if character == current { quote = nil }
                return " "
            }
            if character == "'" || character == "\"" { quote = character; return " " }
            return character
        })
        let functions: Set<String> = ["last", "position", "count", "id", "local-name", "namespace-uri", "name",
            "string", "concat", "starts-with", "contains", "substring-before", "substring-after", "substring",
            "string-length", "normalize-space", "translate", "boolean", "not", "true", "false", "lang",
            "number", "sum", "floor", "ceiling", "round", "node", "text", "comment", "processing-instruction"]
        let pattern = try NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_.-]*(?=\\s*\\()")
        let text = unquoted as NSString
        for match in pattern.matches(in: unquoted, range: NSRange(location: 0, length: text.length)) {
            let name = text.substring(with: match.range)
            if !functions.contains(name) { throw EvaluationError.unsupportedExtension(name) }
        }
        let expression = rule.utf8CString.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: xmlChar.self, capacity: buffer.count) { xmlXPathCompile($0) }
        }
        guard let expression else { throw EvaluationError.invalidXPath(rule) }
        xmlXPathFreeCompExpr(expression)
    }
}
