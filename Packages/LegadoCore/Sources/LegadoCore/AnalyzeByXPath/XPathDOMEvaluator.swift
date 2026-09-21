import Foundation
import SwiftSoup

final class XPathDOMNode: CustomStringConvertible {
    let node: Node
    let owner: Node
    init(node: Node, owner: Node) { self.node = node; self.owner = owner }
    var description: String { (try? node.outerHtml()) ?? "" }
}

private struct XPathDOMItem {
    let node: Node
    var attribute: String?
    var projected: String?
    var identity: String { "\(ObjectIdentifier(node))|\(attribute ?? "")|\(projected ?? "")" }
    var text: String {
        get throws {
            if let projected { return projected }
            if let attribute { return try node.attr(attribute) }
            if let value = node as? TextNode { return value.getWholeText().split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            if let element = node as? Element { return try element.tagName() == "script" ? element.data() : element.text() }
            return try node.outerHtml()
        }
    }
}

private enum XPathDOMValue {
    case nodes([XPathDOMItem]), string(String), number(Double), boolean(Bool)
    var nodes: [XPathDOMItem] { if case .nodes(let values) = self { return values }; return [] }
    var string: String {
        get throws {
            switch self {
            case .nodes(let values): return try values.first?.text ?? ""
            case .string(let value): return value
            case .boolean(let value): return value ? "true" : "false"
            case .number(let value):
                if value.isNaN { return "NaN" }
                if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
                if value == 0 { return "0" }
                return value.rounded() == value ? String(format: "%.0f", value) : String(value)
            }
        }
    }
    var number: Double { get throws { if case .number(let value) = self { return value }; if case .boolean(let value) = self { return value ? 1 : 0 }; return Double(try string.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .nan } }
    var boolean: Bool {
        switch self {
        case .nodes(let values): return !values.isEmpty
        case .string(let value): return !value.isEmpty
        case .number(let value): return value != 0 && !value.isNaN
        case .boolean(let value): return value
        }
    }
}

final class XPathDOMEvaluator {
    private let root: Node
    private let input: XPathDOMItem
    private var order: [ObjectIdentifier: Int] = [:]

    init(_ content: Any) throws {
        if let value = content as? XPathDOMNode { root = value.owner; input = XPathDOMItem(node: value.node) }
        else if let node = content as? Node {
            var owner = node
            while let parent = owner.parent() { owner = parent }
            root = owner; input = XPathDOMItem(node: node)
        } else {
            var text = ruleText(content)
            if text.hasSuffix("</td>") { text = "<tr>" + text + "</tr>" }
            if text.hasSuffix("</tr>") || text.hasSuffix("</tbody>") { text = "<table>" + text + "</table>" }
            let xml = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<?xml")
            let document = try SwiftSoup.parse(text, "", xml ? Parser.xmlParser() : Parser.htmlParser())
            if xml { document.outputSettings().prettyPrint(pretty: false) }
            root = document; input = XPathDOMItem(node: document)
        }
        for (index, node) in descendants(root, includeSelf: true).enumerated() { order[ObjectIdentifier(node)] = index }
    }

    func evaluate(_ expression: XPathDOMExpression) throws -> [Any] {
        let value = try evaluate(expression, item: input, position: 1, count: 1)
        if case .nodes(let nodes) = value {
            return try nodes.map { item -> Any in
                if item.attribute != nil || item.projected != nil || !(item.node is Element) { return try item.text }
                return XPathDOMNode(node: item.node, owner: root)
            }
        }
        return [try value.string]
    }

    private func descendants(_ node: Node, includeSelf: Bool) -> [Node] {
        var result: [Node] = includeSelf ? [node] : []
        var pending = Array(node.getChildNodes().reversed())
        while let next = pending.popLast() { result.append(next); pending += next.getChildNodes().reversed() }
        return result
    }

    private func ordered(_ items: [XPathDOMItem]) -> [XPathDOMItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.identity).inserted }.sorted {
            (order[ObjectIdentifier($0.node)] ?? 0) < (order[ObjectIdentifier($1.node)] ?? 0)
        }
    }

    private func filtered(_ nodes: [XPathDOMItem], predicates: [XPathDOMExpression]) throws -> [XPathDOMItem] {
        var nodes = nodes
        for predicate in predicates {
            let count = nodes.count
            nodes = try nodes.enumerated().filter { index, item in
                let value = try evaluate(predicate, item: item, position: index + 1, count: count)
                if case .number(let number) = value { return number == Double(index + 1) }
                return value.boolean
            }.map(\.element)
        }
        return nodes
    }

    private func evaluate(_ expression: XPathDOMExpression, item: XPathDOMItem, position: Int, count: Int) throws -> XPathDOMValue {
        try Task.checkCancellation()
        switch expression {
        case .literal(let value): return .string(value)
        case .number(let value): return .number(value)
        case .negative(let value): return .number(try -evaluate(value, item: item, position: position, count: count).number)
        case .filter(let base, let predicates):
            return .nodes(try filtered(evaluate(base, item: item, position: position, count: count).nodes, predicates: predicates))
        case .path(let base, let absolute, let steps):
            var nodes = absolute ? [XPathDOMItem(node: root)] : try base.map { try evaluate($0, item: item, position: position, count: count).nodes } ?? [item]
            for step in steps {
                if step.test == "num()", step.axis == "child" {
                    nodes = try filtered(project("num", nodes: nodes), predicates: step.predicates)
                } else {
                    nodes = try ordered(nodes.flatMap { try filtered(select(step, item: $0), predicates: step.predicates) })
                }
            }
            return .nodes(nodes)
        case .function(let name, let arguments):
            let values = try arguments.map { try evaluate($0, item: item, position: position, count: count) }
            return try function(name, values: values, item: item, position: position, count: count)
        case .binary(let operation, let left, let right):
            let a = try evaluate(left, item: item, position: position, count: count)
            if operation == "and", !a.boolean { return .boolean(false) }
            if operation == "or", a.boolean { return .boolean(true) }
            let b = try evaluate(right, item: item, position: position, count: count)
            switch operation {
            case "and": return .boolean(a.boolean && b.boolean)
            case "or": return .boolean(a.boolean || b.boolean)
            case "|": return .nodes(ordered(a.nodes + b.nodes))
            case "+": return .number(try a.number + b.number)
            case "-": return .number(try a.number - b.number)
            case "*": return .number(try a.number * b.number)
            case "div": return .number(try a.number / b.number)
            case "mod": return .number(try a.number.truncatingRemainder(dividingBy: b.number))
            default: return .boolean(try compare(a, b, operation: operation))
            }
        }
    }

    private func select(_ step: XPathDOMStep, item: XPathDOMItem) throws -> [XPathDOMItem] {
        let node = item.node
        if step.test.hasSuffix("()"), !["node()", "text()", "comment()", "allText()", "tidyText()", "num()", "html()", "outerHtml()"].contains(step.test) {
            throw AnalyzeByXPath.EvaluationError.unsupportedExtension(step.test)
        }
        if step.axis == "attribute" {
            guard item.attribute == nil, item.projected == nil, let element = node as? Element else { return [] }
            let names = step.test == "*" ? element.getAttributes()?.asList().map { $0.getKey() } ?? [] : [step.test]
            return try names.filter { try element.hasAttr($0) }.map { XPathDOMItem(node: element, attribute: $0) }
        }
        if step.axis == "child", ["allText()", "tidyText()", "html()", "outerHtml()", "num()"].contains(step.test) {
            return try project(String(step.test.dropLast(2)), nodes: [item])
        }
        let candidates: [Node]
        switch step.axis {
        case "self": candidates = [node]
        case "parent": candidates = item.attribute != nil ? [node] : node.parent().map { [$0] } ?? []
        case "child": candidates = item.attribute == nil ? node.getChildNodes() : []
        case "descendant": candidates = descendants(node, includeSelf: false)
        case "descendant-or-self": candidates = descendants(node, includeSelf: true)
        case "ancestor", "ancestor-or-self":
            var values: [Node] = step.axis == "ancestor-or-self" ? [node] : []
            var parent = node.parent()
            while let current = parent { values.append(current); parent = current.parent() }
            candidates = values
        case "following-sibling", "preceding-sibling", "following-sibling-one", "preceding-sibling-one", "sibling":
            let siblings = node.parent()?.getChildNodes() ?? []
            let index = siblings.firstIndex { $0 === node } ?? 0
            if step.axis == "sibling" { candidates = siblings.filter { $0 !== node } }
            else if step.axis.hasPrefix("following") { candidates = Array(siblings.dropFirst(index + 1)) }
            else { candidates = Array(siblings.prefix(index).reversed()) }
        case "following", "preceding":
            let all = descendants(root, includeSelf: true), index = order[ObjectIdentifier(node)] ?? 0
            if step.axis == "following" {
                let excluded = Set(descendants(node, includeSelf: true).map(ObjectIdentifier.init))
                candidates = all.dropFirst(index + 1).filter { !excluded.contains(ObjectIdentifier($0)) }
            } else {
                var ancestors = Set<ObjectIdentifier>(), parent = node.parent()
                while let current = parent { ancestors.insert(ObjectIdentifier(current)); parent = current.parent() }
                candidates = all.prefix(index).reversed().filter { !ancestors.contains(ObjectIdentifier($0)) }
            }
        default: throw AnalyzeByXPath.EvaluationError.unsupportedExtension(step.axis)
        }
        var results = candidates.filter { candidate in
            if step.test == "node()" { return true }
            if step.test == "text()" { return candidate is TextNode || node.nodeName() == "script" && candidate is DataNode }
            if step.test == "comment()" { return candidate is Comment }
            guard let element = candidate as? Element, !(element is Document) else { return false }
            return step.test == "*" || element.tagName() == step.test
        }.map { XPathDOMItem(node: $0) }
        if step.axis.hasSuffix("-one") { results = Array(results.prefix(1)) }
        return results
    }

    private func project(_ name: String, nodes: [XPathDOMItem]) throws -> [XPathDOMItem] {
        if name == "num" {
            let text = try nodes.map { try $0.text }.joined()
            let regex = try NSRegularExpression(pattern: "[0-9]*\\.?[0-9]+")
            guard let first = nodes.first, let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return [] }
            let value = (text as NSString).substring(with: match.range)
            return [XPathDOMItem(node: first.node, projected: try XPathDOMValue.number(Double(value) ?? .nan).string)]
        }
        return try nodes.compactMap { item in
            guard let element = item.node as? Element else { return nil }
            let value: String
            switch name {
            case "html": value = try element.html()
            case "outerHtml": value = try element.outerHtml()
            case "allText", "tidyText": value = try item.text
            default: throw AnalyzeByXPath.EvaluationError.unsupportedExtension(name)
            }
            return XPathDOMItem(node: element, projected: value)
        }
    }

    private func compare(_ lhs: XPathDOMValue, _ rhs: XPathDOMValue, operation: String) throws -> Bool {
        if operation == "=" || operation == "!=" {
            if case .boolean = lhs { return operation == "!=" ? lhs.boolean != rhs.boolean : lhs.boolean == rhs.boolean }
            if case .boolean = rhs { return operation == "!=" ? lhs.boolean != rhs.boolean : lhs.boolean == rhs.boolean }
        }
        let left = try values(lhs), right = try values(rhs)
        for a in left { for b in right {
            let numeric: Bool
            if case .number = a { numeric = true } else if case .number = b { numeric = true } else { numeric = false }
            let found: Bool
            switch operation {
            case "=": found = try numeric ? a.number == b.number : a.string == b.string
            case "!=": found = try numeric ? a.number != b.number : a.string != b.string
            case "<": found = try a.number < b.number
            case "<=": found = try a.number <= b.number
            case ">": found = try a.number > b.number
            case ">=": found = try a.number >= b.number
            case "^=": found = try a.string.hasPrefix(b.string)
            case "$=": found = try a.string.hasSuffix(b.string)
            case "*=": found = try a.string.contains(b.string)
            case "~=", "!~":
                let regex = try NSRegularExpression(pattern: b.string), text = try a.string
                let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
                found = operation == "~=" ? match : !match
            default: throw AnalyzeByXPath.EvaluationError.invalidXPath(operation)
            }
            if found { return true }
        } }
        return false
    }
    private func values(_ value: XPathDOMValue) throws -> [XPathDOMValue] {
        if case .nodes(let nodes) = value { return try nodes.map { .string(try $0.text) } }
        return [value]
    }

    private func function(_ name: String, values: [XPathDOMValue], item: XPathDOMItem, position: Int, count: Int) throws -> XPathDOMValue {
        func argument(_ index: Int = 0, defaultContext: Bool = false) throws -> XPathDOMValue {
            if values.indices.contains(index) { return values[index] }
            if defaultContext { return .nodes([item]) }
            throw AnalyzeByXPath.EvaluationError.invalidXPath(name)
        }
        let counts: [String: ClosedRange<Int>] = ["position": 0...0, "last": 0...0, "true": 0...0, "false": 0...0,
            "text": 0...0, "allText": 0...0, "tidyText": 0...0, "num": 0...0, "html": 0...0, "outerHtml": 0...0,
            "count": 1...1, "string": 0...1, "number": 0...1, "boolean": 1...1, "not": 1...1,
            "contains": 2...2, "starts-with": 2...2, "concat": 2...Int.max, "normalize-space": 0...1,
            "string-length": 0...1, "sum": 1...1, "floor": 1...1, "ceiling": 1...1, "round": 1...1,
            "name": 0...1, "local-name": 0...1, "namespace-uri": 0...1, "substring-before": 2...2, "substring-after": 2...2,
            "substring": 2...3, "translate": 3...3, "id": 1...1, "lang": 1...1]
        if let range = counts[name], !range.contains(values.count) { throw AnalyzeByXPath.EvaluationError.invalidXPath(name) }
        switch name {
        case "position": return .number(Double(position))
        case "last": return .number(Double(count))
        case "true": return .boolean(true)
        case "false": return .boolean(false)
        case "text": return .nodes(try select(.init(axis: "child", test: "text()"), item: item))
        case "allText", "tidyText", "num", "html", "outerHtml": return .nodes(try project(name, nodes: [item]))
        case "count": return .number(Double(try argument().nodes.count))
        case "string": return .string(try argument(defaultContext: true).string)
        case "number": return .number(try argument(defaultContext: true).number)
        case "boolean": return .boolean(try argument().boolean)
        case "not": return .boolean(try !argument().boolean)
        case "contains": return .boolean(try argument().string.contains(argument(1).string))
        case "starts-with": return .boolean(try argument().string.hasPrefix(argument(1).string))
        case "concat": return .string(try values.map { try $0.string }.joined())
        case "normalize-space": return .string(try argument(defaultContext: true).string.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        case "string-length": return .number(Double(try argument(defaultContext: true).string.unicodeScalars.count))
        case "sum": return .number(try argument().nodes.reduce(0) { try $0 + (Double($1.text) ?? .nan) })
        case "floor": return .number(try floor(argument().number))
        case "ceiling": return .number(try ceil(argument().number))
        case "round": return .number(try floor(argument().number + 0.5))
        case "namespace-uri":
            let target = values.isEmpty ? item : values[0].nodes.first
            guard let target else { return .string("") }
            let tag = target.attribute ?? target.node.nodeName()
            let prefix = tag.contains(":") ? String(tag.split(separator: ":").first ?? "") : ""
            if target.attribute != nil && prefix.isEmpty { return .string("") }
            let key = prefix.isEmpty ? "xmlns" : "xmlns:" + prefix
            var node: Node? = target.node
            while let current = node {
                if try current.hasAttr(key) { return .string(try current.attr(key)) }
                node = current.parent()
            }
            return .string("")
        case "id":
            let keys = Set(try argument().string.split(whereSeparator: \.isWhitespace).map(String.init))
            return .nodes(try descendants(root, includeSelf: true).compactMap { node in
                guard let element = node as? Element, keys.contains(try element.attr("id")) else { return nil }
                return XPathDOMItem(node: element)
            })
        case "lang":
            let language = try argument().string.lowercased()
            var node: Node? = item.node
            while let current = node {
                let value = try current.hasAttr("xml:lang") ? current.attr("xml:lang") : current.attr("lang")
                if !value.isEmpty { return .boolean(value.lowercased() == language || value.lowercased().hasPrefix(language + "-")) }
                node = current.parent()
            }
            return .boolean(false)
        case "name", "local-name":
            let target = values.isEmpty ? item : values[0].nodes.first
            let tag = target?.attribute ?? target?.node.nodeName() ?? ""
            return .string(tag == "#document" ? "" : name == "local-name" ? String(tag.split(separator: ":").last ?? "") : tag)
        case "substring-before", "substring-after":
            let text = try argument().string, needle = try argument(1).string
            guard let range = text.range(of: needle) else { return .string("") }
            return .string(name == "substring-before" ? String(text[..<range.lowerBound]) : String(text[range.upperBound...]))
        case "substring":
            let text = Array(try argument().string.unicodeScalars), start = try floor(argument(1).number + 0.5)
            let end = values.count > 2 ? try start + floor(argument(2).number + 0.5) : .infinity
            return .string(String(String.UnicodeScalarView(text.enumerated().filter { Double($0.offset + 1) >= start && Double($0.offset + 1) < end }.map(\.element))))
        case "translate":
            let text = try argument().string.unicodeScalars, from = Array(try argument(1).string.unicodeScalars), to = Array(try argument(2).string.unicodeScalars)
            let result = text.compactMap { value -> Unicode.Scalar? in
                guard let index = from.firstIndex(of: value) else { return value }
                return to.indices.contains(index) ? to[index] : nil
            }
            return .string(String(String.UnicodeScalarView(result)))
        default: throw AnalyzeByXPath.EvaluationError.unsupportedExtension(name)
        }
    }
}
