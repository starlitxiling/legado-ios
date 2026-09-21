import Foundation
import SwiftSoup

public final class EpubParser {
    public let title: String
    public let author: String
    public let tocNodes: [LocalBookTocNode]
    public var cover: Data? { coverPath.flatMap { try? archive.readEntry($0) } }
    private let coverPath: String?
    let archive: ZipReader
    private let spine: [String]
    private let navigation: [(title: String, href: String)]

    public convenience init(url: URL) throws { try self.init(archive: ZipReader(url: url)) }

    public convenience init(data: Data) throws { try self.init(archive: ZipReader(data: data)) }

    init(archive: ZipReader) throws {
        self.archive = archive
        let container = try Self.xml(archive.readEntry("META-INF/container.xml"))
        guard let root = container.descendants("rootfile").first?.attributes["full-path"] else {
            throw LocalBookError.invalidEPUB("缺少 OPF 路径")
        }
        let opf = try Self.xml(archive.readEntry(root))
        title = opf.descendants("title").first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        author = opf.descendants("creator").first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let items = opf.descendants("item")
        var manifest: [String: String] = [:]
        for item in items {
            if let id = item.attributes["id"], let href = item.attributes["href"] {
                manifest[id] = try Self.resolve(href, relativeTo: root)
            }
        }
        let spine = opf.descendants("itemref").compactMap { manifest[$0.attributes["idref"] ?? ""] }
        guard !spine.isEmpty, spine.allSatisfy({ archive.entryNames.contains($0) }) else { throw LocalBookError.invalidEPUB("spine 为空或引用文件缺失") }
        self.spine = spine
        let coverID = opf.descendants("meta").first { $0.attributes["name"] == "cover" }?.attributes["content"]
        let coverItem = items.first { ($0.attributes["properties"] ?? "").split(separator: " ").contains("cover-image") }
        coverPath = manifest[coverItem?.attributes["id"] ?? coverID ?? ""]
        var nodes: [LocalBookTocNode] = []
        func appendNode(title: String, href: String?, path: String, parent: Int?, depth: Int) throws -> Int {
            guard depth <= 64, nodes.count < 10_000 else { throw LocalBookError.invalidEPUB("Navigation exceeds supported depth or node count") }
            let id = nodes.count
            nodes.append(LocalBookTocNode(id: id, parentId: parent, depth: depth,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                href: try href.map { try Self.resolve($0, relativeTo: path) }))
            return id
        }
        if let nav = items.first(where: { ($0.attributes["properties"] ?? "").split(separator: " ").contains("nav") }),
           let path = manifest[nav.attributes["id"] ?? ""] {
            let doc = try Self.xml(archive.readEntry(path))
            let toc = doc.descendants("nav").first { ($0.attributes["epub:type"] ?? $0.attributes["type"] ?? "").split(separator: " ").contains("toc") }
                ?? doc.descendants("nav").first
            func visit(_ container: EpubXMLNode, parent: Int?, depth: Int) throws {
                for child in container.children {
                    if child.name == "li" {
                        let label = child.children.first { $0.name == "a" || $0.name == "span" }
                        let id = try appendNode(title: label?.text ?? "", href: label?.attributes["href"], path: path, parent: parent, depth: depth)
                        for list in child.children where list.name == "ol" || list.name == "ul" {
                            try visit(list, parent: id, depth: depth + 1)
                        }
                    } else if child.name == "ol" || child.name == "ul" {
                        try visit(child, parent: parent, depth: depth)
                    }
                }
            }
            if let toc { try visit(toc, parent: nil, depth: 0) }
        }
        if nodes.isEmpty {
            let ncxID = opf.descendants("spine").first?.attributes["toc"]
                ?? items.first { $0.attributes["media-type"] == "application/x-dtbncx+xml" }?.attributes["id"]
            if let path = manifest[ncxID ?? ""] {
                let ncx = try Self.xml(archive.readEntry(path))
                func visit(_ container: EpubXMLNode, parent: Int?, depth: Int) throws {
                    for point in container.children where point.name == "navPoint" {
                        let href = point.children.first { $0.name == "content" }?.attributes["src"]
                        let title = point.children.first { $0.name == "navLabel" }?.text ?? ""
                        let id = try appendNode(title: title, href: href, path: path, parent: parent, depth: depth)
                        try visit(point, parent: id, depth: depth + 1)
                    }
                }
                if let map = ncx.descendants("navMap").first { try visit(map, parent: nil, depth: 0) }
            }
        }
        tocNodes = nodes
        let navigation = nodes.compactMap { node in node.href.map { (title: node.title, href: $0) } }
        var seen = Set<String>()
        self.navigation = navigation.filter { archive.entryNames.contains(Self.parts($0.href).path) && seen.insert($0.href).inserted }
    }

    var cacheCost: Int {
        archive.byteCount + title.utf8.count + author.utf8.count + spine.reduce(0) { $0 + $1.utf8.count }
            + tocNodes.reduce(0) { $0 + $1.title.utf8.count + ($1.href?.utf8.count ?? 0) + 32 }
    }

    private func readingEntries() -> [(title: String, href: String)] {
        guard !navigation.isEmpty else { return spine.map { ("", $0) } }
        var entries = navigation
        if let first = entries.first, let index = spine.firstIndex(of: Self.parts(first.href).path) {
            entries.insert(contentsOf: spine.prefix(index).map { ("卷首", $0) }, at: 0)
        }
        return entries
    }

    public func chapters(bookURL: String) throws -> [BookChapter] {
        var entries = navigation
        if entries.isEmpty {
            entries = try spine.enumerated().map { index, path in
                let doc = try SwiftSoup.parse(archive.readEntry(path) ?? Data(), "")
                let name = try doc.title()
                return (name.isEmpty ? "第\(index + 1)章" : name, path)
            }
        } else if let first = entries.first, let index = spine.firstIndex(of: Self.parts(first.href).path) {
            entries.insert(contentsOf: spine.prefix(index).map { ("卷首", $0) }, at: 0)
        }
        return entries.enumerated().map { index, entry in
            var chapter = BookChapter()
            chapter.index = index; chapter.bookUrl = bookURL; chapter.baseUrl = bookURL
            chapter.url = entry.href; chapter.title = entry.title; chapter.resourceUrl = Self.parts(entry.href).path
            chapter.startFragmentId = Self.parts(entry.href).fragment
            chapter.endFragmentId = index + 1 < entries.count ? Self.parts(entries[index + 1].href).fragment : nil
            return chapter
        }
    }

    public func content(chapter: BookChapter) throws -> String {
        let entries = readingEntries()
        guard let index = entries.firstIndex(where: { $0.href == chapter.url }), let href = chapter.url else {
            throw LocalBookError.invalidEPUB("目录章节不存在")
        }
        let start = Self.parts(href)
        let next = index + 1 < entries.count ? Self.parts(entries[index + 1].href) : nil
        var paths = [start.path]
        if let from = spine.firstIndex(of: start.path) {
            let to = next.flatMap { spine.firstIndex(of: $0.path) } ?? spine.count
            if to > from {
                paths = Array(spine[from..<to])
                if let next, next.fragment != nil, to < spine.count { paths.append(next.path) }
            }
        }
        return try paths.map { path in
            guard let data = try archive.readEntry(path) else { throw LocalBookError.invalidEPUB("缺少正文 \(path)") }
            if path.contains("titlepage.xhtml") || path.contains("cover") { return "<img src=\"cover.jpeg\">" }
            let doc = try SwiftSoup.parse(data, "")
            try doc.select("script, style").remove()
            guard let body = doc.body() else { return "" }
            var html = try body.html()
            if path == start.path, let fragment = start.fragment {
                guard let node = try doc.getElementById(fragment), let range = html.range(of: try node.outerHtml()) else {
                    throw LocalBookError.invalidEPUB("缺少锚点 \(fragment)")
                }
                html = String(html[range.lowerBound...])
            }
            if let next, path == next.path, let fragment = next.fragment,
               let node = try doc.getElementById(fragment), let range = html.range(of: try node.outerHtml()) {
                html = String(html[..<range.lowerBound])
            }
            let fragment = try SwiftSoup.parseBodyFragment(html)
            for image in try fragment.select("img, image") {
                let source = try image.tagName() == "image" ? image.attr("xlink:href") : image.attr("src")
                try image.tagName("img")
                let href = source.trimmingCharacters(in: .whitespacesAndNewlines)
                if ["http", "https", "data"].contains(URL(string: href)?.scheme?.lowercased() ?? "") {
                    try image.attr("src", href)
                } else { try image.attr("src", Self.resolve(href, relativeTo: path)) }
            }
            return HtmlFormatter.formatKeepImg(try fragment.body()?.html())
        }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
    }

    public func getImage(_ href: String) throws -> Data? {
        if href == "cover.jpeg" { return cover }
        let path = href.removingPercentEncoding ?? href
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else {
            throw LocalBookError.invalidEPUB("Invalid image resource path")
        }
        return try archive.readEntry(path)
    }

    private static func parts(_ href: String) -> (path: String, fragment: String?) {
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        return (String(parts[0]), parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil)
    }

    private static func resolve(_ href: String, relativeTo path: String) throws -> String {
        guard let base = URL(string: "https://epub.invalid/" + path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!),
              let url = URL(string: href, relativeTo: base)?.absoluteURL, url.host == "epub.invalid", url.scheme == "https" else {
            throw LocalBookError.invalidEPUB("非法资源路径")
        }
        return String(url.standardized.path.dropFirst()) + (url.fragment.map { "#" + ($0.removingPercentEncoding ?? $0) } ?? "")
    }

    private static func xml(_ data: Data?) throws -> EpubXMLNode {
        guard let data else { throw LocalBookError.invalidEPUB("XML 文件缺失") }
        let delegate = EpubXMLDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { throw LocalBookError.invalidEPUB("XML 格式错误") }
        return root
    }
}

private final class EpubXMLNode {
    let name: String
    let attributes: [String: String]
    var children: [EpubXMLNode] = []
    var text = ""
    init(name: String, attributes: [String: String]) { self.name = name; self.attributes = attributes }
    func descendants(_ name: String) -> [EpubXMLNode] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
    }
}

private final class EpubXMLDelegate: NSObject, XMLParserDelegate {
    var root: EpubXMLNode?
    var stack: [EpubXMLNode] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let node = EpubXMLNode(name: String(elementName.split(separator: ":").last ?? ""), attributes: attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { for node in stack { node.text += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) { for node in stack { node.text += text } }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = stack.popLast()
    }
}
