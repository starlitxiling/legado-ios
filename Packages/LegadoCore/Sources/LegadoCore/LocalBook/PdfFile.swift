import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

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
    public let tocNodes: [LocalBookTocNode]
    private let ranges: [(title: String, start: Int, end: Int)]
    public var title: String { document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? "" }
    public var author: String { document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String ?? "" }

    public init(url: URL, pagesPerChapter: Int = 10, useBookmarks: Bool = false) throws {
        guard pagesPerChapter > 0 else { throw PdfFileError.invalidChapter }
        guard let document = PDFDocument(url: url) else { throw PdfFileError.invalidDocument }
        guard !document.isLocked else { throw PdfFileError.locked }
        guard document.pageCount > 0 else { throw PdfFileError.invalidDocument }
        self.document = document
        var nodes: [LocalBookTocNode] = []
        var visited = Set<ObjectIdentifier>()
        func visit(_ outline: PDFOutline, parent: Int?, depth: Int) {
            guard depth <= 64, nodes.count < 10_000, visited.insert(ObjectIdentifier(outline)).inserted else { return }
            let destination = outline.destination ?? (outline.action as? PDFActionGoTo)?.destination
            let page = destination?.page.map { document.index(for: $0) }
            let validPage = page.flatMap { (0..<document.pageCount).contains($0) ? $0 : nil }
            let id = nodes.count
            nodes.append(LocalBookTocNode(id: id, parentId: parent, depth: depth,
                title: outline.label ?? "", pageIndex: validPage))
            for index in 0..<outline.numberOfChildren {
                if let child = outline.child(at: index) { visit(child, parent: id, depth: depth + 1) }
            }
        }
        if let root = document.outlineRoot {
            for index in 0..<root.numberOfChildren {
                if let child = root.child(at: index) { visit(child, parent: nil, depth: 0) }
            }
        }
        tocNodes = nodes
        var bookmarks: [(String, Int)] = useBookmarks ? nodes.compactMap { node in node.pageIndex.map { (node.title, $0) } } : []
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
                return ("分段_\(start / pagesPerChapter)", start, end)
            }
        }
    }

    public func chapters(bookURL: String) -> [BookChapter] {
        ranges.enumerated().map { index, range in
            var chapter = BookChapter()
            chapter.index = index; chapter.bookUrl = bookURL; chapter.baseUrl = bookURL
            chapter.title = range.title; chapter.url = "pdf_\(index)"
            chapter.start = Int64(range.start); chapter.end = Int64(range.end)
            return chapter
        }
    }

    public func content(chapter: BookChapter) throws -> String {
        let start: Int, end: Int
        let address = chapter.url ?? ""
        if address.hasPrefix("pdf_"), let index = Int(address.dropFirst(4)), ranges.indices.contains(index) {
            (start, end) = (ranges[index].start, ranges[index].end)
        } else {
            let parts = address.split(separator: ":")
            guard parts.count == 3, parts[0] == "pdf", let lower = Int(parts[1]), let upper = Int(parts[2]),
                  lower >= 0, lower < upper, upper <= document.pageCount else { throw PdfFileError.invalidChapter }
            (start, end) = (lower, upper)
        }
        return (start..<end).map { "<img src=\"\($0)\" >\n" }.joined()
    }

    public func getImage(_ href: String, width: Int = 1536) throws -> Data? {
        try Task.checkCancellation()
        guard let index = Int(href), (0..<document.pageCount).contains(index), (1...4096).contains(width),
              let page = document.page(at: index)?.pageRef else { throw PdfFileError.invalidChapter }
        let bounds = page.getBoxRect(.cropBox)
        let rotated = abs(page.rotationAngle) % 180 == 90
        let pageWidth = rotated ? bounds.height : bounds.width
        let pageHeight = rotated ? bounds.width : bounds.height
        guard pageWidth > 0, pageHeight > 0 else { throw PdfFileError.invalidDocument }
        let scaledHeight = (Double(width) * pageHeight / pageWidth).rounded(.up)
        guard scaledHeight.isFinite, scaledHeight >= 1, scaledHeight <= 8192,
              scaledHeight * Double(width) <= 16_777_216 else { throw PdfFileError.invalidDocument }
        let height = Int(scaledHeight)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PdfFileError.invalidDocument }
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(target)
        context.scaleBy(x: Double(width) / pageWidth, y: Double(height) / pageHeight)
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: pageRect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        try Task.checkCancellation()
        guard let image = context.makeImage() else { throw PdfFileError.invalidDocument }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw PdfFileError.invalidDocument
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PdfFileError.invalidDocument }
        return output as Data
    }
}
