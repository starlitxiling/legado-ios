import XCTest
import PDFKit
import ImageIO
@testable import LegadoCore

final class LocalIllustratedBookTests: XCTestCase {
    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/localbook/" + name)
    }

    func testEpubTreeRetainsDuplicateAndUnlinkedLabelsWithoutDuplicatingReadingChapters() throws {
        for kind in ["nav", "ncx"] {
            let parser = try EpubParser(url: fixture("nested-\(kind).epub"))
            XCTAssertEqual(parser.tocNodes.map(\.id), [0, 1, 2, 3, 4])
            XCTAssertEqual(parser.tocNodes.map(\.parentId), [nil, 0, 1, 0, nil])
            XCTAssertEqual(parser.tocNodes.map(\.depth), [0, 1, 2, 1, 0])
            XCTAssertEqual(parser.tocNodes.map(\.title), ["Part", "One", "Alias", "Two", "Last"])
            XCTAssertNil(parser.tocNodes[0].href)
            let chapters = try parser.chapters(bookURL: "fixture:epub")
            XCTAssertEqual(chapters.map(\.title), ["卷首", "One", "Two", "Last"])
            XCTAssertEqual(try parser.content(chapter: chapters[0]), "<img src=\"cover.jpeg\">")
            let content = try parser.content(chapter: chapters[1])
            XCTAssertTrue(content.contains("<img src=\"OPS/images/picture.png\">"))
            XCTAssertFalse(content.contains("script-hidden"))
            XCTAssertFalse(content.contains("style-hidden"))
            XCTAssertFalse(content.contains("Second body"))
            XCTAssertNotNil(CGImageSourceCreateWithData(try XCTUnwrap(parser.getImage("OPS/images/picture.png")) as CFData, nil))
            XCTAssertEqual(try parser.getImage("cover.jpeg"), parser.cover)
            XCTAssertTrue(try parser.content(chapter: XCTUnwrap(chapters.last)).contains("Final page"))
        }
    }

    func testLocalImageProviderReadsArchiveWithoutHTTP() async throws {
        let parsed = try LocalBook.parse(url: fixture("nested-nav.epub"))
        let client = ReplayHttpClient()
        let loader = ImageDownloader(client: client, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let image = try await loader.load(url: "legado-local://book/OPS/images/picture.png", book: parsed.book, isCover: false)
        XCTAssertNotNil(CGImageSourceCreateWithData(image as CFData, nil))
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertThrowsError(try LocalBook.image(book: parsed.book, href: "../outside"))
    }

    func testGeneratedMobiAZWAndAZW3ReadFinalChapterAndRealBitmap() throws {
        for ext in ["mobi", "azw3", "azw"] {
            let parsed = try LocalBook.parse(url: fixture("illustrated." + ext))
            XCTAssertEqual(parsed.book.name, "Illustrated " + ext.uppercased())
            let content = try LocalBook.content(book: parsed.book, chapter: XCTUnwrap(parsed.chapters.last))
            XCTAssertTrue(content.contains("The final page."))
            let href = ext == "azw3" ? "kindle:embed:0001?mime=image/png" : "recindex:1"
            XCTAssertTrue(content.contains(href))
            let data = try XCTUnwrap(LocalBook.image(book: parsed.book, href: href))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }
    }
}
