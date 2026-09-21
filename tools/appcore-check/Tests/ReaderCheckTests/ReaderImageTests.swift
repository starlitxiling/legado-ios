import XCTest
import LegadoCore
@testable import ReaderCheck

final class ReaderImageTests: XCTestCase {
    func testImageClickModesRespectScriptsPreviewAndLegacyFallback() throws {
        let image = ReaderPlacedImage(offset: 1, url: #"https://image.test/a,{"js":"legacy()"}"#, click: "click()", rect: .zero)
        XCTAssertEqual(try ReaderImageAction.resolve(image, mode: "0", taps: 1, onlineText: true), .script("click()", image.url))
        XCTAssertEqual(try ReaderImageAction.resolve(image, mode: "1", taps: 1, onlineText: true), .preview)
        XCTAssertEqual(try ReaderImageAction.resolve(image, mode: "3", taps: 1, onlineText: true), .none)
        XCTAssertEqual(try ReaderImageAction.resolve(image, mode: "4", taps: 1, onlineText: true), .consume)
        XCTAssertEqual(try ReaderImageAction.resolve(image, mode: "4", taps: 2, onlineText: true), .script("click()", image.url))
        let legacy = ReaderPlacedImage(offset: 1, url: image.url, click: nil, rect: .zero)
        XCTAssertEqual(try ReaderImageAction.resolve(legacy, mode: "2", taps: 1, onlineText: true), .script("legacy()", "https://image.test/a"))
        XCTAssertEqual(try ReaderImageAction.resolve(legacy, mode: "2", taps: 1, onlineText: false), .none)
    }

    func testImageStylesFlowInlineFullWidthAndSinglePage() throws {
        let size = CGSize(width: 400, height: 700)
        let body = ["Before<img src='https://image.test/a'>After"]
        let sizes = ["https://image.test/a": CGSize(width: 100, height: 50)]
        let normal = try Paginator().paginate(title: "", paragraphs: body, size: size, settings: ReaderSettings(), imageStyle: "DEFAULT", imageSizes: sizes)
        let full = try Paginator().paginate(title: "", paragraphs: body, size: size, settings: ReaderSettings(), imageStyle: "FULL", imageSizes: sizes)
        let inline = try Paginator().paginate(title: "", paragraphs: body, size: size, settings: ReaderSettings(), imageStyle: "TEXT", imageSizes: sizes)
        let single = try Paginator().paginate(title: "", paragraphs: body, size: size, settings: ReaderSettings(), imageStyle: "SINGLE", imageSizes: sizes)
        XCTAssertEqual(normal.pages.count, 1); XCTAssertEqual(full.pages.count, 1); XCTAssertEqual(inline.pages.count, 1)
        XCTAssertEqual(single.pages.count, 3)
        XCTAssertEqual(normal.pages[0].images[0].rect.width, 100)
        XCTAssertEqual(full.pages[0].images[0].rect.width, full.contentSize.width)
        XCTAssertLessThan(inline.pages[0].images[0].rect.width, 100)
        XCTAssertEqual(Set([normal.text.string, full.text.string, inline.text.string, single.text.string]), ["Before After"])
    }

    func testImageJSONOptionsPreserveClickStyleAndWidth() throws {
        let body = [#"Before<img src="https://image.test/a,{"width":"50%","style":"DEFAULT","click":"java.toast(src)"}">After"#]
        let page = try Paginator().paginate(title: "", paragraphs: body, size: CGSize(width: 400, height: 700), settings: ReaderSettings(), imageStyle: "SINGLE")
        let image = try XCTUnwrap(page.pages.flatMap(\.images).first)
        XCTAssertEqual(image.click, "java.toast(src)")
        XCTAssertEqual(image.rect.width, page.contentSize.width * 0.5)
        XCTAssertTrue(image.url.contains("width"))
    }

    func testAndroidSingleImageOffsetUsesOneSpace() throws {
        let pagination = try Paginator().paginate(title: "", paragraphs: ["<img src='https://example.org/very-long-name.png'>后文"],
            size: CGSize(width: 390, height: 700), settings: ReaderSettings())
        XCTAssertEqual(pagination.text.string, " 后文")
        XCTAssertEqual(pagination.pages[0].range.length, 1)
        XCTAssertEqual(pagination.pageIndex(at: 1), 1)
        XCTAssertEqual(pagination.firstCharacterOffset(on: 1), 1)
    }

    func testImageOnlyParagraphsDoNotCreateBlankPages() throws {
        let pagination = try Paginator().paginate(title: "", paragraphs: ["　　<img src='/a'>", "　　<img src='/b'>"],
            size: CGSize(width: 390, height: 700), settings: ReaderSettings(), imageBaseURL: "https://example.org/chapter")
        XCTAssertEqual(pagination.pages.count, 2)
        XCTAssertEqual(pagination.pages.map(\.imageURL), ["https://example.org/a", "https://example.org/b"])
        XCTAssertEqual(pagination.pages.map { $0.text.string }.joined(), pagination.text.string)
    }

    func testImageOccupiesItsOwnPageAndPreservesOffsets() throws {
        let pagination = try Paginator().paginate(title: "标题", paragraphs: ["前文<img src='https://example.org/a.png'>后文"],
            size: CGSize(width: 390, height: 700), settings: ReaderSettings())
        let images = pagination.pages.filter { $0.imageURL != nil }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.imageURL, "https://example.org/a.png")
        XCTAssertEqual(pagination.pages.map { $0.text.string }.joined(), pagination.text.string)
        XCTAssertTrue(pagination.pages.last?.text.string.contains("后文") == true)
        for index in pagination.pages.indices {
            XCTAssertEqual(pagination.pageIndex(at: pagination.firstCharacterOffset(on: index)), index)
        }
    }
    func testLocalBookImagesResolveAgainstArchiveRoot() throws {
        var book = Book(); book.bookUrl = "file:///book.epub"; book.origin = "loc_book"
        var chapter = BookChapter(); chapter.url = "OPS/chapter.xhtml"; chapter.baseUrl = book.bookUrl
        let input = ReaderLayoutInput(book: book, chapter: chapter,
            rawContent: "<img src=\"OPS/images/picture.png\">", rules: [])
        let result = try ReaderLayout.build(input: input, size: CGSize(width: 390, height: 700),
            settings: ReaderSettings(), didStart: {})
        XCTAssertEqual(result.pagination.pages.compactMap(\.imageURL), ["legado-local://book/OPS/images/picture.png"])
    }

    @MainActor
    func testScannedPDFLoadsIntoReaderAsImagePagesWithoutHTTP() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/localbook/scanned.pdf")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let parsed = try LocalBook.parse(url: fixture)
        let db = try AppDatabase.inMemory()
        try await LocalBook.save(book: parsed.book, chapters: parsed.chapters, database: db)
        let client = ReplayHttpClient()
        let model = ReaderViewModel(database: db, client: client, cacheDirectory: root, preDownloadCount: { 0 })
        await model.load(bookURL: fixture.absoluteString)
        XCTAssertNil(model.errorMessage)
        let images = try XCTUnwrap(model.pagination).pages.compactMap(\.imageURL)
        XCTAssertEqual(images, ["legado-local://book/0", "legado-local://book/1"])
        let bytes = try await ImageDownloader(client: client, cacheDirectory: root).load(url: images[1], book: parsed.book, isCover: false)
        XCTAssertFalse(bytes.isEmpty)
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
        await model.close()
    }

}
