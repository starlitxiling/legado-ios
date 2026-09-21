import XCTest
import PDFKit
import ImageIO
@testable import LegadoCore

final class PdfImageParityTests: XCTestCase {
    func testScannedPagesRenderAndOutlineKeepsGroupsAndDepth() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/localbook/scanned.pdf")
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertTrue(document.page(at: 0)?.string?.isEmpty != false)
        let parser = try PdfFile(url: url)
        XCTAssertEqual(parser.tocNodes.map(\.title), ["Part", "Last scan"])
        XCTAssertEqual(parser.tocNodes.map(\.parentId), [nil, 0])
        XCTAssertEqual(parser.tocNodes.map(\.depth), [0, 1])
        XCTAssertEqual(parser.tocNodes.map(\.pageIndex), [nil, 1])
        let chapter = try XCTUnwrap(parser.chapters(bookURL: url.absoluteString).first)
        XCTAssertEqual(chapter.url, "pdf_0")
        XCTAssertEqual(try parser.content(chapter: chapter), "<img src=\"0\" >\n<img src=\"1\" >\n")
        let image = try XCTUnwrap(parser.getImage("1", width: 400))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(image as CFData, nil))
        let bitmap = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(bitmap.width, 400); XCTAssertEqual(bitmap.height, 600)
        let pixels = try XCTUnwrap(bitmap.dataProvider?.data) as Data
        XCTAssertGreaterThan(Set(pixels).count, 1)
        XCTAssertThrowsError(try parser.getImage("-1"))
        XCTAssertThrowsError(try parser.getImage("2"))
        XCTAssertThrowsError(try parser.getImage("0", width: 0))
        var legacy = chapter; legacy.url = "pdf:0:2"
        XCTAssertEqual(try parser.content(chapter: legacy), try parser.content(chapter: chapter))
        let parsed = try LocalBook.parse(url: url)
        XCTAssertNotNil(try LocalBook.image(book: parsed.book, href: "legado-local://book/1"))
    }
}
