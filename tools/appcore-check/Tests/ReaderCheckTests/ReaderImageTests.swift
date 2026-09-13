import XCTest
@testable import ReaderCheck

final class ReaderImageTests: XCTestCase {
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
}
