import XCTest
import PDFKit
import CoreText
@testable import LegadoCore

final class MobiPdfTests: XCTestCase {
    private func file(_ ext: String, data: Data) throws -> URL {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/tmp")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString + "." + ext)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testPalmDocBackReferencesAndInvalidInput() throws {
        XCTAssertEqual(try PalmDocDecoder.decompress(Data([65, 66, 67, 0x80, 0x1b, 0xc4])), Data("ABCABCABC D".utf8))
        XCTAssertThrowsError(try PalmDocDecoder.decompress(Data([0x80])))
        XCTAssertThrowsError(try PalmDocDecoder.decompress(Data([0x80, 0])))
        XCTAssertThrowsError(try PalmDocDecoder.decompress(Data([3, 65])))
    }

    func testMobiImportAndChapterContent() throws {
        for ext in ["mobi", "azw3"] {
            let url = try file(ext, data: Self.mobi())
            let parsed = try LocalBook.parse(url: url)
            XCTAssertEqual(parsed.book.name, "合成书名")
            XCTAssertEqual(parsed.book.author, "测试作者")
            XCTAssertEqual(parsed.chapters.map(\.title), ["第一章", "第二章"])
            XCTAssertEqual(try LocalBook.chapterList(book: parsed.book).count, 2)
            guard parsed.chapters.count == 2 else { return }
            XCTAssertTrue(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[0]).contains("Alpha Alpha"))
            XCTAssertFalse(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[0]).contains("Beta"))
            XCTAssertTrue(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[1]).contains("Beta"))
        }
    }

    func testMalformedMobiIsRejected() throws {
        let url = try file("mobi", data: Data(repeating: 0, count: 78))
        XCTAssertThrowsError(try LocalBook.parse(url: url))
    }

    static func pdf(pageCount: Int = 2) throws -> Data {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        for page in 0..<pageCount {
            let text = page == 0 ? "First page text" : page == 1 ? "Second page text" : "Page \(page + 1) text"
            context.beginPDFPage(nil)
            context.textPosition = CGPoint(x: 20, y: 300)
            let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 16, nil)])
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            context.endPDFPage()
        }
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: data as Data)?.dataRepresentation())
    }

    func testPDFPagesAndGrouping() throws {
        let document = try XCTUnwrap(PDFDocument(data: Self.pdf()))
        let outline = PDFOutline(), bookmark = PDFOutline()
        bookmark.label = "全书"
        bookmark.destination = PDFDestination(page: try XCTUnwrap(document.page(at: 0)), at: .zero)
        outline.insertChild(bookmark, at: 0); document.outlineRoot = outline
        let url = try file("pdf", data: XCTUnwrap(document.dataRepresentation()))
        let parsed = try LocalBook.parse(url: url)
        XCTAssertEqual(parsed.chapters.count, 1)
        guard parsed.chapters.count == 1 else { return }
        XCTAssertTrue(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[0]).contains("First page text"))
        XCTAssertTrue(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[0]).contains("Second page text"))
        let grouped = try PdfFile(url: url, pagesPerChapter: 10)
        let chapters = grouped.chapters(bookURL: url.absoluteString)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertTrue(try grouped.content(chapter: chapters[0]).contains("Second page text"))
        XCTAssertThrowsError(try PdfFile(url: url, pagesPerChapter: 0))
        let bookmarked = try PdfFile(url: url, useBookmarks: true)
        XCTAssertEqual(bookmarked.chapters(bookURL: url.absoluteString).map(\.title), ["全书"])
        var invalid = BookChapter(); invalid.url = "pdf:-1:2"
        XCTAssertThrowsError(try grouped.content(chapter: invalid))
        invalid.url = "pdf:0:3"
        XCTAssertThrowsError(try grouped.content(chapter: invalid))
    }

    func testPDFDefaultGroupingThroughLocalBook() throws {
        for (pages, count) in [(1, 1), (10, 1), (11, 2)] {
            let url = try file("pdf", data: Self.pdf(pageCount: pages))
            let parsed = try LocalBook.parse(url: url)
            XCTAssertEqual(parsed.chapters.count, count, "\(pages) pages")
            XCTAssertEqual(try LocalBook.chapterList(book: parsed.book).count, count)
            let last = try XCTUnwrap(parsed.chapters.last)
            let text = try LocalBook.content(book: parsed.book, chapter: last)
            XCTAssertTrue(text.contains(pages == 1 ? "First page text" : "Page \(pages) text"))
            if pages == 11 { XCTAssertFalse(text.contains("Page 10 text")) }
        }
    }

    static func mobi() -> Data {
        func put(_ data: inout Data, _ offset: Int, _ value: Int, _ size: Int = 4) {
            for index in 0..<size { data[offset + index] = UInt8(truncatingIfNeeded: value >> ((size - index - 1) * 8)) }
        }
        let html = Data("<html><body><h1>第一章</h1><p>Alpha Alpha</p><mbp:pagebreak/><h1>第二章</h1><p>Beta</p></body></html>".utf8)
        var compressed = Data()
        for start in stride(from: 0, to: html.count, by: 8) {
            let end = min(start + 8, html.count)
            compressed.append(UInt8(end - start)); compressed.append(html[start..<end])
        }
        var exth = Data("EXTH".utf8) + Data(repeating: 0, count: 8)
        for (type, text) in [(503, "合成书名"), (100, "测试作者")] {
            let bytes = Data(text.utf8), offset = exth.count
            exth.append(Data(repeating: 0, count: 8)); put(&exth, offset, type); put(&exth, offset + 4, bytes.count + 8); exth.append(bytes)
        }
        put(&exth, 4, exth.count); put(&exth, 8, 2)
        var header = Data(repeating: 0, count: 264)
        put(&header, 0, 2, 2); put(&header, 4, html.count); put(&header, 8, 1, 2); put(&header, 10, 4096, 2)
        header.replaceSubrange(16..<20, with: Data("MOBI".utf8)); put(&header, 20, 248)
        put(&header, 28, 65001); put(&header, 36, 6); put(&header, 108, 0xffffffff)
        put(&header, 128, 0x40); put(&header, 244, 0xffffffff)
        header.append(exth)
        var pdb = Data(repeating: 0, count: 96)
        pdb.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8)); put(&pdb, 76, 2, 2)
        put(&pdb, 78, pdb.count); put(&pdb, 86, pdb.count + header.count)
        return pdb + header + compressed
    }
}
