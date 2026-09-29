import XCTest
@testable import LegadoCore

final class WebFileResolverTests: XCTestCase {
    func testNormalizedNameMatchesAndroidRules() {
        XCTAssertEqual(WebFileResolver.normalizedName("book", rawSuffix: "txt"), "book.txt")
        XCTAssertEqual(WebFileResolver.normalizedName("book.zip", rawSuffix: ".epub"), "book.epub")
        XCTAssertEqual(WebFileResolver.normalizedName("book.zip", rawSuffix: "epub", replaceExistingSuffix: false), "book.zip.epub")
        XCTAssertEqual(WebFileResolver.normalizedName("book.EPUB", rawSuffix: "epub"), "book.EPUB")
        XCTAssertEqual(WebFileResolver.normalizedName("book", rawSuffix: "../x"), "book")
        XCTAssertEqual(WebFileResolver.normalizedName("book", rawSuffix: nil), "book")
        XCTAssertEqual(WebFileResolver.normalizedName("...", rawSuffix: "txt"), "...")
    }

    func testFilesUsePathNameOrBookNameWithTypeOption() {
        var book = Book(now: 0); book.name = "三体"; book.author = "刘慈欣"
        let files = WebFileResolver.files(book: book, downloadURLs: [
            "https://dl.test/files/%E4%B8%89%E4%BD%93.epub",
            #"https://dl.test/get?id=1,{"type":"txt"}"#,
            "https://dl.test/get?id=2"
        ])
        XCTAssertEqual(files.map(\.name), ["三体.epub", "三体 作者：刘慈欣.txt", "三体 作者：刘慈欣"])
        XCTAssertEqual(files.map(\.isSupported), [true, true, false])
    }

    func testDownloadUsesContentDispositionWhenPathHasNoName() async throws {
        var source = BookSource(); source.bookSourceUrl = "https://dl.test"; source.bookSourceName = "下载源"
        var book = Book(now: 0); book.name = "书"; book.bookUrl = "https://dl.test/book"
        let file = WebFileResolver.files(book: book, downloadURLs: ["https://dl.test/get?id=2"])[0]
        let download = try await WebFileResolver.download(file, source: source, book: book, client: WebFileClient())
        XCTAssertEqual(download.name, "真名.txt")
        XCTAssertEqual(String(decoding: download.data, as: UTF8.self), "正文")
        let empty = WebFile(url: "https://dl.test/empty.txt", name: "empty.txt")
        do { _ = try await WebFileResolver.download(empty, source: source, book: book, client: WebFileClient()); XCTFail() }
        catch { XCTAssertEqual(error as? WebFileError, .empty("empty.txt")) }
        XCTAssertEqual(WebFileResolver.sanitized("a/b:c"), "a_b_c")
        XCTAssertEqual(WebFileResolver.sanitized(".."), "download")
    }
}

private struct WebFileClient: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        if request.url.path == "/empty.txt" { return HttpResponse(status: 200, body: Data(), finalURL: request.url) }
        return HttpResponse(status: 200, body: Data("正文".utf8), finalURL: request.url,
                            headers: ["Content-Disposition": "attachment; filename*=UTF-8''%E7%9C%9F%E5%90%8D.txt"])
    }
}
