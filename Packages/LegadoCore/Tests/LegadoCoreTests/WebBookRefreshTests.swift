import XCTest
@testable import LegadoCore

final class WebBookRefreshTests: XCTestCase {
    private func source(script: String) -> BookSource {
        var source = BookSource()
        source.bookSourceUrl = "https://refresh.test"
        source.searchUrl = "/search"
        source.ruleSearch = SearchRule()
        source.ruleSearch?.bookList = "tag.a"
        source.ruleSearch?.name = "text"
        source.ruleSearch?.author = "data-author"
        source.ruleSearch?.bookUrl = "href"
        source.ruleBookInfo = BookInfoRule()
        source.ruleBookInfo?.tocUrl = "tag.nav@data-url"
        source.ruleToc = TocRule()
        source.ruleToc?.preUpdateJs = script
        source.ruleToc?.chapterList = "tag.a"
        source.ruleToc?.chapterName = "text"
        source.ruleToc?.chapterUrl = "href"
        return source
    }

    private func book() -> Book {
        var book = Book(now: 0)
        book.name = "Book"; book.author = "Author"
        book.bookUrl = "https://refresh.test/book"
        book.tocUrl = "https://refresh.test/old-toc"
        book.variable = #"{"kept":"value"}"#
        return book
    }

    private func enqueue(_ client: ReplayHttpClient, _ path: String, _ body: String) async {
        let url = URL(string: "https://refresh.test" + path)!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data(body.utf8), finalURL: url))
    }

    func testPreUpdateRefreshesTocAndUpdatesScriptBookSnapshot() async throws {
        let source = source(script: "java.refreshTocUrl();if(book.tocUrl!=='https://refresh.test/new-toc')throw 'stale book';")
        let client = ReplayHttpClient()
        await enqueue(client, "/book", "<nav data-url='/new-toc'></nav>")
        await enqueue(client, "/new-toc", "<a href='/chapter'>Chapter</a>")
        var book = book()
        let chapters = try await WebBook(source: source, client: client).chapterList(book: &book, runPreUpdate: true)
        XCTAssertEqual(chapters.first?.title, "Chapter")
        XCTAssertEqual(book.tocUrl, "https://refresh.test/new-toc")
        XCTAssertEqual(try JsBookBinding(book).value(for: "kept"), "value")
        let requests = await client.requests
        XCTAssertEqual(requests.map { $0.url.path }, ["/book", "/new-toc"])
    }

    func testReGetBookFindsExactMatchBeforeRefreshingInfo() async throws {
        let source = source(script: "java.reGetBook();if(book.bookUrl!=='https://refresh.test/replacement')throw 'stale book';")
        let client = ReplayHttpClient()
        await enqueue(client, "/search", "<a href='/replacement' data-author='Author'>Book</a>")
        await enqueue(client, "/replacement", "<nav data-url='/new-toc'></nav>")
        await enqueue(client, "/new-toc", "<a href='/chapter'>Chapter</a>")
        var book = book()
        let chapters = try await WebBook(source: source, client: client).chapterList(book: &book, runPreUpdate: true)
        XCTAssertEqual(book.bookUrl, "https://refresh.test/replacement")
        XCTAssertEqual(chapters.first?.bookUrl, book.bookUrl)
        XCTAssertEqual(try JsBookBinding(book).value(for: "kept"), "value")
    }

    func testRefreshSkipsRepeatedDetailsAndPreUpdateIsOptIn() async throws {
        for fromInfo in [false, true] {
            let source = source(script: "java.refreshTocUrl()")
            let client = ReplayHttpClient()
            await enqueue(client, "/old-toc", "<a href='/chapter'>Chapter</a>")
            var book = book()
            _ = try await WebBook(source: source, client: client).chapterList(book: &book,
                runPreUpdate: fromInfo, fromBookInfo: fromInfo)
            let requests = await client.requests
            XCTAssertEqual(requests.map { $0.url.path }, ["/old-toc"])
        }
    }

    func testRefreshHostIsRejectedOutsidePreUpdateAndRawElementsKeepScalar() throws {
        let engine = JsEngine()
        let parser = AnalyzeRule(content: "<p>Body</p>", engines: [.js: engine])
        for method in ["reGetBook", "refreshTocUrl"] {
            XCTAssertThrowsError(try parser.getString("@js:java." + method + "()")) {
                XCTAssertTrue(String(describing: $0).contains("preUpdateJs"))
            }
        }
        XCTAssertEqual(try parser.getElementsRaw("@js:42") as? Double, 42)
        XCTAssertTrue(try parser.getElements("@js:42").isEmpty)
        XCTAssertEqual(try parser.getString("@js:typeof java.getElementsRaw('@js:42')"), "number")
    }
}
