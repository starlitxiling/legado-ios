import Foundation
import SwiftSoup
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct RssPage: Sendable {
    public var articles: [RssArticle]
    public var nextPageURL: String?
}

public struct RssParser {
    public init() {}

    public func parse(_ body: String, source: RssSource, sort: String = "", baseURL: String,
                      engine: JsEngine? = nil) throws -> RssPage {
        guard let rule = source.ruleArticles?.trimmingCharacters(in: .whitespacesAndNewlines), !rule.isEmpty else {
            let delegate = FeedXMLDelegate(source: source, sort: sort, baseURL: baseURL)
            let parser = XMLParser(data: Data(body.utf8))
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse() else { throw parser.parserError ?? RssError.invalidXML }
            return RssPage(articles: delegate.articles, nextPageURL: nil)
        }
        let variables = RuleVariableStore()
        let parser = Self.analyzer(body, baseURL: baseURL, engine: engine, ruleData: variables)
        let items = try parser.getElements(rule.hasPrefix("-") ? String(rule.dropFirst()) : rule)
        var next: String?
        if source.ruleNextPage?.uppercased() == "PAGE" { next = baseURL }
        else if let value = source.ruleNextPage, !value.isEmpty {
            let extracted = try parser.getString(value)
            if !extracted.isEmpty { next = Self.absolute(extracted, base: baseURL) }
        }
        var articles: [RssArticle] = []
        let listVariables = variables.variables
        for item in items {
            for key in Array(variables.variables.keys) { variables.setValue(nil, for: key) }
            for (key, value) in listVariables { variables.setValue(value, for: key) }
            parser.setContent(item)
            let title = try parser.getString(source.ruleTitle)
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            var article = RssArticle(origin: source.sourceUrl, title: title)
            article.sort = sort; article.type = source.type
            article.pubDate = try parser.getString(source.rulePubDate)
            article.description = source.ruleDescription?.isEmpty == false ? try parser.getString(source.ruleDescription) : nil
            do {
                let image = try parser.getString(source.ruleImage)
                if !image.isEmpty { article.image = Self.absolute(image, base: source.sourceUrl) }
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                engine?.logger("RSS 图片规则失败：\(error)")
            }
            article.link = Self.absolute(try parser.getString(source.ruleLink), base: baseURL)
            article.variable = String(decoding: try JSONEncoder().encode(variables.variables), as: UTF8.self)
            articles.append(article)
        }
        if rule.hasPrefix("-") { articles.reverse() }
        return RssPage(articles: articles, nextPageURL: next)
    }

    public static func absolute(_ value: String, base: String) -> String {
        guard !value.isEmpty else { return "" }
        return URL(string: value, relativeTo: URL(string: base))?.absoluteURL.absoluteString ?? value
    }

    static func analyzer(_ body: Any, baseURL: String, engine: JsEngine?, ruleData: RuleVariableStore? = nil) -> AnalyzeRule {
        var engines: [RuleMode: any SelectorEngine] = [.default: AnalyzeByJSoup(), .xpath: AnalyzeByXPath(), .json: AnalyzeByJSonPath()]
        engines[.js] = engine ?? JsEngine(baseUrl: baseURL)
        let parser = AnalyzeRule(content: body, engines: engines, ruleData: ruleData)
        parser.scriptBaseUrl = baseURL
        return parser
    }
}

public enum RssError: Error { case invalidXML, invalidSource, invalidURL, httpStatus(Int), paginationLimit }

private final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    let source: RssSource
    let sort: String
    let baseURL: String
    var articles: [RssArticle] = []
    private var article: RssArticle?
    private var stack: [(name: String, text: String, markup: String, attributes: [String: String], hasChildren: Bool)] = []
    private var itemDepth = 0

    init(source: RssSource, sort: String, baseURL: String) {
        self.source = source; self.sort = sort; self.baseURL = baseURL
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let name = name.lowercased()
        if !stack.isEmpty { stack[stack.count - 1].hasChildren = true }
        stack.append((name, "", "", attributes, false))
        if name == "item" || name == "entry" {
            article = RssArticle(origin: source.sourceUrl)
            article?.sort = sort; article?.type = source.type
            itemDepth = stack.count
        }
        guard article != nil else { return }
        if name == "link", let href = attributes["href"], attributes["rel"] == nil || attributes["rel"] == "alternate" {
            article?.link = RssParser.absolute(href, base: baseURL)
        }
        if name == "media:thumbnail" || (name == "enclosure" && attributes["type"]?.hasPrefix("image/") == true) {
            article?.image = attributes["url"].map { RssParser.absolute($0, base: baseURL) }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !stack.isEmpty {
            stack[stack.count - 1].text += string
            stack[stack.count - 1].markup += escaped(string)
        }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self))
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let element = stack.popLast() else { return }
        if article != nil, stack.count == itemDepth {
            let value = (element.hasChildren ? element.markup : element.text).trimmingCharacters(in: .whitespacesAndNewlines)
            switch element.name {
            case "title": article?.title = value
            case "link": if !value.isEmpty { article?.link = RssParser.absolute(value, base: baseURL) }
            case "description", "summary": article?.description = value
            case "content:encoded", "content": article?.content = value
            case "pubdate", "published", "dc:date": article?.pubDate = value
            case "updated": if article?.pubDate == nil { article?.pubDate = value }
            default: break
            }
        }
        if element.name == "item" || element.name == "entry" {
            if var article {
                if article.image == nil {
                    let html = (article.description ?? "") + (article.content ?? "")
                    if let image = try? SwiftSoup.parseBodyFragment(html).select("img[src]").first()?.attr("src"), !image.isEmpty {
                        article.image = RssParser.absolute(image, base: baseURL)
                    }
                }
                articles.append(article)
            }
            article = nil
        } else if !stack.isEmpty {
            stack[stack.count - 1].text += element.text
            let attributes = element.attributes.sorted { $0.key < $1.key }.map { " \($0.key)=\"\(escaped($0.value))\"" }.joined()
            stack[stack.count - 1].markup += "<\(element.name)\(attributes)>\(element.markup)</\(element.name)>"
        }
    }
    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
