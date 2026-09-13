import Foundation
import SwiftSoup

enum MobiReadMetrics {
    private static let lock = NSLock()
    private static var observer: ((URL, Int) -> Void)?
    static func observe(_ observer: ((URL, Int) -> Void)?) {
        lock.lock(); defer { lock.unlock() }; self.observer = observer
    }
    static func decoded(_ url: URL, record: Int) {
        lock.lock(); let observer = observer; lock.unlock()
        observer?(url, record)
    }
}

public final class MobiFile {
    private let book: MobiBook
    public var title: String { book.header.title }
    public var author: String { book.header.author }
    public var cover: Data? { try? book.getCover() }
    var cacheCost: Int { book.cacheCost }
    public init(url: URL) throws {
        book = try MobiBook(data: Data(contentsOf: url, options: .mappedIfSafe), onRecordDecoded: { MobiReadMetrics.decoded(url, record: $0) })
    }
    public func chapters(bookURL: String) -> [BookChapter] {
        book.directory.enumerated().map { index, node in
            var chapter = BookChapter()
            chapter.index = index; chapter.bookUrl = bookURL; chapter.baseUrl = bookURL
            chapter.title = node.title; chapter.url = "mobi:\(index)"; chapter.isVolume = node.isVolume
            return chapter
        }
    }
    public func content(chapter: BookChapter) throws -> String {
        let parts = (chapter.url ?? "").split(separator: ":")
        guard parts.count == 2, parts[0] == "mobi", let index = Int(parts[1]), book.directory.indices.contains(index) else {
            throw MobiError.invalid("章节编号无效")
        }
        guard let sectionIndex = book.directory[index].sectionIndex else { return "" }
        let doc = try SwiftSoup.parse(book.sections[sectionIndex].html)
        try doc.select("title, script, style, [style*=display:none]").remove()
        for image in try doc.select("img") {
            let alt = try image.attr("alt")
            try image.before(alt.isEmpty ? "[图片]" : "[图片：\(alt)]"); try image.remove()
        }
        return HtmlFormatter.format(try doc.body()?.html())
    }
    public func getImage(_ href: String) throws -> Data? { try book.getResourceByHref(href) }
}
