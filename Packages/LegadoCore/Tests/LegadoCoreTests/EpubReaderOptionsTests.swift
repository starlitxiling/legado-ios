import XCTest
@testable import LegadoCore

final class EpubReaderOptionsTests: XCTestCase {
    func testTagOptionsRemoveHeadingAndRubyAnnotationsWithoutLosingBaseText() throws {
        let parser = try EpubParser(data: BackupReviewTests.archive([
            "META-INF/container.xml": "<container><rootfiles><rootfile full-path='book.opf'/></rootfiles></container>",
            "book.opf": "<package><metadata><title>Tags</title></metadata><manifest><item id='a' href='a.xhtml'/></manifest><spine><itemref idref='a'/></spine></package>",
            "a.xhtml": "<html><body><h1>Heading</h1><p><ruby>Base<rp>(</rp><rt>Reading</rt><rp>)</rp></ruby> Body</p></body></html>"
        ]))
        let chapter = try XCTUnwrap(parser.chapters(bookURL: "book.epub").first)
        let original = try parser.content(chapter: chapter)
        XCTAssertTrue(original.contains("Heading")); XCTAssertTrue(original.contains("Reading"))
        let cleaned = try parser.content(chapter: chapter, deletingTags: 2 | 4)
        XCTAssertFalse(cleaned.contains("Heading")); XCTAssertFalse(cleaned.contains("Reading"))
        XCTAssertTrue(cleaned.contains("Base")); XCTAssertTrue(cleaned.contains("Body"))
    }
}
