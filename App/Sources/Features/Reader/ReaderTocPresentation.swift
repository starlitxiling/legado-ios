import Foundation
import LegadoCore

struct ReaderTocEntry: Identifiable, Equatable {
    let id: String
    let parent: String?
    let depth: Int
    let title: String
    let chapterIndex: Int?
    var pageIndex: Int? = nil
}

enum ReaderTocPresentation {
    static func entries(chapters: [BookChapterRow], nodes: [LocalBookTocNode], includeUnlisted: Bool = true) -> [ReaderTocEntry] {
        if nodes.isEmpty {
            guard includeUnlisted else { return [] }
            var volume: String?
            return chapters.map { chapter in
                let id = "chapter:\(chapter.index)"
                if chapter.isVolume { volume = id }
                return ReaderTocEntry(id: id, parent: chapter.isVolume ? nil : volume, depth: !chapter.isVolume && volume != nil ? 1 : 0,
                                      title: chapter.title, chapterIndex: chapter.index)
            }
        }
        var listed = Set<Int>()
        var result = nodes.map { node in
            let chapter = chapters.first { chapter in
                if let page = node.pageIndex, let start = chapter.start, let end = chapter.end { return Int64(page) >= start && Int64(page) < end }
                return node.href != nil && node.href == chapter.url
            }
            if let chapter { listed.insert(chapter.index) }
            return ReaderTocEntry(id: "node:\(node.id)", parent: node.parentId.map { "node:\($0)" }, depth: node.depth,
                                  title: node.title, chapterIndex: chapter?.index, pageIndex: node.pageIndex)
        }
        if includeUnlisted {
            result += chapters.filter { !listed.contains($0.index) }.map {
                ReaderTocEntry(id: "chapter:\($0.index)", parent: nil, depth: 0, title: $0.title, chapterIndex: $0.index)
            }
        }
        return result
    }

    static func ancestors(of id: String, in entries: [ReaderTocEntry]) -> Set<String> {
        let parents = Dictionary(entries.map { ($0.id, $0.parent) }, uniquingKeysWith: { first, _ in first })
        return ancestors(of: id, parents: parents)
    }

    private static func ancestors(of id: String, parents: [String: String?]) -> Set<String> {
        var result = Set<String>(), next = parents[id] ?? nil
        while let parent = next, parent != id, result.insert(parent).inserted { next = parents[parent] ?? nil }
        return result
    }

    static func visible(_ entries: [ReaderTocEntry], collapsed: Set<String>, query: String, reversed: Bool) -> [ReaderTocEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let parents = Dictionary(entries.map { ($0.id, $0.parent) }, uniquingKeysWith: { first, _ in first })
        let result: [ReaderTocEntry]
        if query.isEmpty {
            result = entries.filter { ancestors(of: $0.id, parents: parents).isDisjoint(with: collapsed) }
        } else {
            var matches = Set<String>()
            for item in entries where item.title.localizedCaseInsensitiveContains(query) {
                matches.insert(item.id); matches.formUnion(ancestors(of: item.id, parents: parents))
            }
            result = entries.filter { matches.contains($0.id) }
        }
        return reversed ? Array(result.reversed()) : result
    }

    static func bookmarkMarkdown(name: String, author: String, bookmarks: [BookmarkRow]) -> String {
        "## \(name) \(author)\n\n" + bookmarks.map {
            "#### \($0.chapterName)\n\n###### 原文\n \($0.bookText)\n\n###### 摘要\n \($0.content)\n\n"
        }.joined()
    }
}
