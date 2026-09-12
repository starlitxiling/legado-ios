import Foundation
import Kanna
import SwiftSoup

/// JsoupXpath README NodeTest：自有文本、全部文本、HTML 与首个数字的终端投影。
struct XPathProjection {
    let path: String
    let name: String

    init?(_ rule: String) throws {
        let pattern = try NSRegularExpression(pattern: "(?:^|/)(text|allText|html|outerHtml|num)\\s*\\(\\s*\\)\\s*$")
        let source = rule as NSString
        guard let match = pattern.firstMatch(in: rule, range: NSRange(location: 0, length: source.length)) else { return nil }
        name = source.substring(with: match.range(at: 1))
        let prefix = source.substring(to: match.range.location)
        if prefix.isEmpty { path = "." }
        else if prefix.hasSuffix("/") { path = prefix + "descendant-or-self::*" }
        else { path = prefix }
    }

    func value(_ node: Kanna.XMLElement) throws -> String? {
        guard node.xpath("self::*").count > 0 else { return nil }
        if name == "html" { return node.innerHTML ?? "" }
        if name == "outerHtml" { return node.toHTML ?? "" }
        // 片段已由 libxml2 成树，避免 HTML 解析再次丢弃孤立 td 等节点。
        let document = try SwiftSoup.parse(node.toHTML ?? "", "", Parser.xmlParser())
        guard let element = try document.select(node.tagName ?? "*").first() else { return nil }
        switch name {
        case "text": return try element.ownText()
        case "allText": return try element.text()
        default:
            let text = try element.ownText() as NSString
            let number = try NSRegularExpression(pattern: "[+-]?(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)")
            guard let match = number.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) else { return nil }
            return text.substring(with: match.range)
        }
    }
}
