import Foundation
import PDFKit

public enum PdfFileError: Error, LocalizedError {
    case invalidDocument
    case locked
    case invalidChapter
    public var errorDescription: String? {
        switch self {
        case .invalidDocument: return "PDF 文件无效或没有页面"
        case .locked: return "PDF 文件已加密，需要先解锁"
        case .invalidChapter: return "PDF 章节页码无效"
        }
    }
}

public final class PdfFile {
    private let document: PDFDocument
    private let ranges: [(title: String, start: Int, end: Int)]
    public var title: String { document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? "" }
    public var author: String { document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String ?? "" }

    public init(url: URL, pagesPerChapter: Int = 10, useBookmarks: Bool = false) throws {
        guard pagesPerChapter > 0 else { throw PdfFileError.invalidChapter }
        guard let document = PDFDocument(url: url) else { throw PdfFileError.invalidDocument }
        guard !document.isLocked else { throw PdfFileError.locked }
        guard document.pageCount > 0 else { throw PdfFileError.invalidDocument }
        self.document = document
        var bookmarks: [(String, Int)] = []
        func visit(_ outline: PDFOutline, depth: Int = 0) {
            guard depth < 64 else { return }
            let destination = outline.destination ?? (outline.action as? PDFActionGoTo)?.destination
            if let page = destination?.page {
                let index = document.index(for: page)
                if index >= 0 && index < document.pageCount { bookmarks.append((outline.label ?? "第 \(index + 1) 页", index)) }
            }
            for index in 0..<outline.numberOfChildren { if let child = outline.child(at: index) { visit(child, depth: depth + 1) } }
        }
        if useBookmarks, let root = document.outlineRoot { visit(root) }
        bookmarks.sort { $0.1 < $1.1 }
        var starts: [(String, Int)] = []
        for bookmark in bookmarks where starts.last?.1 != bookmark.1 { starts.append(bookmark) }
        if !starts.isEmpty {
            if starts[0].1 > 0 { starts.insert(("卷首", 0), at: 0) }
            ranges = starts.enumerated().map { index, value in
                (value.0, value.1, index + 1 < starts.count ? starts[index + 1].1 : document.pageCount)
            }
        } else {
            ranges = stride(from: 0, to: document.pageCount, by: pagesPerChapter).map { start in
                let end = start + min(pagesPerChapter, document.pageCount - start)
                return (end == start + 1 ? "第 \(start + 1) 页" : "第 \(start + 1)–\(end) 页", start, end)
            }
        }
    }

    public func chapters(bookURL: String) -> [BookChapter] {
        ranges.enumerated().map { index, range in
            var chapter = BookChapter()
            chapter.index = index; chapter.bookUrl = bookURL; chapter.baseUrl = bookURL
            chapter.title = range.title; chapter.url = "pdf:\(range.start):\(range.end)"
            return chapter
        }
    }

    public func content(chapter: BookChapter) throws -> String {
        let parts = (chapter.url ?? "").split(separator: ":")
        guard parts.count == 3, parts[0] == "pdf", let start = Int(parts[1]), let end = Int(parts[2]),
              start >= 0, start < end, end <= document.pageCount else { throw PdfFileError.invalidChapter }
        return (start..<end).map { document.page(at: $0)?.string ?? "" }.joined(separator: "\n\n")
    }
}
