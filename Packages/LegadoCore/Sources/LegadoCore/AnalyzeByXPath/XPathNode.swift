import Foundation
import Kanna
import SwiftSoup

/// 规格 §4；AnalyzeByXPath.kt:17-23：保留节点与所属文档，支持继续求值。
public final class XPathNode: CustomStringConvertible {
    let node: Kanna.XMLElement

    init(_ node: Kanna.XMLElement) { self.node = node }

    var isElement: Bool { node.xpath("self::*").count > 0 }

    /// 规格 §11 U7：元素序列化使用 libxml2；格式与 JsoupXpath 尚未核实。
    public var description: String { isElement ? node.toHTML ?? "" : node.text ?? "" }
}

struct XPathDocument {
    let root: any Kanna.Searchable

    init(_ content: Any) throws {
        if let value = content as? XPathNode, value.isElement {
            root = value.node
            return
        }
        let element = content as? SwiftSoup.Element
        var html = try element?.outerHtml() ?? ruleText(content)
        if html.hasSuffix("</td>") { html = "<tr>" + html + "</tr>" }
        if html.hasSuffix("</tr>") || html.hasSuffix("</tbody>") { html = "<table>" + html + "</table>" }
        let document: any Kanna.XMLDocument
        if html.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<?xml") {
            document = try Kanna.XML(xml: html, encoding: .utf8)
        } else {
            document = try Kanna.HTML(html: html, encoding: .utf8)
        }
        if let element, !(element is SwiftSoup.Document),
           let node = document.xpath("//*[name() = '\(element.tagName())']").first {
            root = node
        } else {
            // Kanna 的文档求值未设置 context.node，相对路径需显式绑定文档节点。
            root = document.xpath("/").first ?? document
        }
    }
}
