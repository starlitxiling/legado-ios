import Foundation
import SwiftSoup

/// 规格 §5、§6：Default 私有语法与 @CSS:，也可绑定节点直接求值。
public final class AnalyzeByJSoup: SelectorEngine {
    public enum EvaluationError: Error { case missingContent, invalidIndex, missingSelectorArgument, missingCSSKeyword }

    private let element: Element?

    /// 规格 §4：通过 SelectorEngine 接收每次求值的内容。
    public init() { element = nil }

    /// 规格 §5.1：绑定原节点，后续 html 删除操作在同一 DOM 上可见。
    public init(_ content: Any) throws { element = try Self.parse(content) }

    static func parse(_ content: Any) throws -> Element {
        if let element = content as? Element { return element }
        let text = ruleText(content)
        let isXML = text.lowercased().hasPrefix("<?xml")
        let parser = isXML ? Parser.xmlParser() : Parser.htmlParser()
        let document = try SwiftSoup.parse(text, "", parser)
        if isXML { document.outputSettings().prettyPrint(pretty: false) }
        return document
    }

    /// 规格 §4：元素入口返回原节点；字符串入口用换行连接字符串列表。
    public func evaluate(_ rule: String, content: Any, operation: RuleOperation, context: AnalyzeRule) throws -> Any? {
        let root = try context.jsoupRoot(for: content)
        switch operation {
        case .element, .elements: return try elements(root, rule)
        case .stringList: return try strings(root, rule)
        case .string:
            let values = try strings(root, rule)
            return values.isEmpty ? nil : values.joined(separator: "\n")
        }
    }

    /// 规格 §5、§6：空匹配返回 nil。
    public func getString(_ rule: String) throws -> String? {
        let values = try getStringList(rule)
        return values.isEmpty ? nil : values.joined(separator: "\n")
    }

    /// 规格 §5.2：空原始规则返回空列表。
    public func getStringList(_ rule: String) throws -> [String] {
        guard let element else { throw EvaluationError.missingContent }
        return try strings(element, rule)
    }

    /// 规格 §6：%% 的首个元素列表为空时结果也为空。
    public func getElements(_ rule: String) throws -> [Element] {
        guard let element else { throw EvaluationError.missingContent }
        return try elements(element, rule)
    }

    private func sourceRule(_ rule: String) -> (css: Bool, rule: String) {
        let css = rule.prefix(5).lowercased() == "@css:"
        return (css, css ? asciiTrim(String(rule.dropFirst(5))) : rule)
    }

    private func combine<T>(_ lists: [[T]], type: String) -> [T] {
        guard type == "%%", let first = lists.first else { return lists.flatMap { $0 } }
        return first.indices.flatMap { index in lists.compactMap { index < $0.count ? $0[index] : nil } }
    }

    private func strings(_ root: Element, _ rawRule: String) throws -> [String] {
        guard !rawRule.isEmpty else { return [] }
        let source = sourceRule(rawRule)
        guard !source.rule.isEmpty else { return [root.data()] }
        let analyzer = RuleAnalyzer(source.rule)
        let rules = try analyzer.splitRule(separators: ["&&", "||", "%%"])
        var lists: [[String]] = []
        for rule in rules {
            let values: [String]
            if source.css {
                guard let at = rule.lastIndex(of: "@") else { throw EvaluationError.missingCSSKeyword }
                values = try result(try root.select(String(rule[..<at])).array(), String(rule[rule.index(after: at)...]))
            } else if rule.isEmpty {
                values = []
            } else {
                let chain = RuleAnalyzer(rule)
                try chain.trim()
                let parts = try chain.splitRule(separators: ["@"])
                var selected = [root]
                for part in parts.dropLast() { selected = try selected.flatMap { try single($0, part) } }
                values = selected.isEmpty ? [] : try result(selected, parts.last!)
            }
            if !values.isEmpty { lists.append(values) }
            if analyzer.elementsType == "||", !values.isEmpty { break }
        }
        return combine(lists, type: analyzer.elementsType)
    }

    private func elements(_ root: Element, _ rawRule: String) throws -> [Element] {
        guard !rawRule.isEmpty else { return [] }
        let source = sourceRule(rawRule)
        let analyzer = RuleAnalyzer(source.rule)
        let rules = try analyzer.splitRule(separators: ["&&", "||", "%%"])
        var lists: [[Element]] = []
        for rule in rules {
            let selected: [Element]
            if source.css {
                selected = try root.select(rule).array()
            } else {
                let chain = RuleAnalyzer(rule)
                try chain.trim()
                let parts = try chain.splitRule(separators: ["@"])
                if parts.count > 1 {
                    var current = [root]
                    for part in parts { current = try current.flatMap { try elements($0, part) } }
                    selected = current
                } else { selected = try single(root, rule) }
            }
            lists.append(selected)
            if analyzer.elementsType == "||", !selected.isEmpty { break }
        }
        return combine(lists, type: analyzer.elementsType)
    }

    private func result(_ elements: [Element], _ keyword: String) throws -> [String] {
        if keyword == "html" || keyword == "all" {
            let selected = Elements(elements)
            if keyword == "html" {
                try selected.select("script").remove()
                try selected.select("style").remove()
            }
            let html = try selected.outerHtml()
            return keyword == "html" && html.isEmpty ? [] : [html]
        }
        var values: [String] = []
        for element in elements {
            let value: String
            switch keyword {
            case "text": value = try element.text()
            case "ownText": value = try element.ownText()
            case "textNodes": value = element.textNodes().map { asciiTrim($0.text()) }.filter { !$0.isEmpty }.joined(separator: "\n")
            default:
                value = try element.attr(keyword)
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || values.contains(value) { continue }
            }
            if !value.isEmpty { values.append(value) }
        }
        return values
    }

    private func single(_ root: Element, _ rule: String) throws -> [Element] {
        let index = try JSoupIndex(rule)
        let parts = index.selector.components(separatedBy: ".")
        let selected: [Element]
        switch parts[0] {
        case "" where index.selector.isEmpty: selected = root.children().array()
        case "children": selected = root.children().array()
        case "class", "tag", "id", "text":
            guard parts.count > 1 else { throw EvaluationError.missingSelectorArgument }
            switch parts[0] {
            case "class": selected = try root.getElementsByClass(parts[1]).array()
            case "tag": selected = try root.getElementsByTag(parts[1]).array()
            case "id": selected = try root.getAllElements().array().filter { $0.id() == parts[1] }
            default: selected = try root.getElementsContainingOwnText(parts[1]).array()
            }
        default: selected = try root.select(index.selector).array()
        }
        return index.apply(selected)
    }
}
