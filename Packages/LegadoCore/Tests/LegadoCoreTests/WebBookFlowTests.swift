import XCTest
@testable import LegadoCore

final class WebBookFlowTests: XCTestCase {
    private func source() -> BookSource {
        var source = BookSource()
        source.bookSourceUrl = "https://flow.test"
        source.searchUrl = "/search"
        source.ruleSearch = SearchRule()
        source.ruleSearch?.bookList = "tag.a"
        source.ruleSearch?.name = "text"
        source.ruleSearch?.bookUrl = "href"
        source.ruleBookInfo = BookInfoRule()
        source.ruleBookInfo?.name = "tag.h1@text"
        source.ruleToc = TocRule()
        source.ruleToc?.chapterList = "tag.a"
        source.ruleToc?.chapterName = "text"
        source.ruleToc?.chapterUrl = "href"
        source.ruleContent = ContentRule()
        source.ruleContent?.content = "tag.p@text"
        return source
    }

    private func enqueue(_ client: ReplayHttpClient, path: String, body: String, status: Int = 200) async {
        let url = URL(string: "https://flow.test" + path)!
        await client.enqueue(url: url, response: HttpResponse(status: status, body: Data(body.utf8), finalURL: url))
    }

    func testURLSideEffectExpressionCanLeaveLeadingWhitespace() async throws {
        var source = source()
        source.searchUrl = "{{cookie.removeCookie(source.getKey())}}\n /search"
        let client = ReplayHttpClient()
        await enqueue(client, path: "/search", body: "<a href='/book'>Book</a>")
        let results = try await WebBook(source: source, client: client).search(key: "x")
        XCTAssertEqual(results.first?.name, "Book")
    }

    func testDetailFallbackPreservesPOSTRuleAndDistinguishesRedirects() async throws {
        for mode in ["direct", "redirect", "script"] {
            var source = source()
            let options = #",{"method":"POST","body":"key={{key}}"}"#
            source.searchUrl = "/lookup" + options
            source.ruleSearch?.bookList = "class.missing"
            if mode == "script" {
                source.loginCheckJs = "({body:function(){return result.body()},url:function(){return 'https://flow.test/rewritten'}})"
            }
            let requestURL = URL(string: "https://flow.test/lookup")!
            let finalURL = mode == "redirect" ? URL(string: "https://flow.test/book")! : requestURL
            let client = ReplayHttpClient()
            await client.enqueue(url: requestURL, method: "POST", response: HttpResponse(status: 200,
                body: Data("<h1>Book</h1>".utf8), finalURL: finalURL))
            let results = try await WebBook(source: source, client: client).search(key: "query")
            let result = try XCTUnwrap(results.first)
            XCTAssertEqual(result.bookUrl, mode == "redirect" ? finalURL.absoluteString
                : "https://flow.test/lookup" + options.replacingOccurrences(of: "{{key}}", with: "query"))
            let requests = await client.requests
            XCTAssertEqual(requests.first?.method, "POST")
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testLoginCheckTransformsEveryWebBookFlowWithoutSessionWrapper() async throws {
        var source = source()
        source.loginUrl = "function checked(body){return body.replace(/OLD/g,'NEW')}"
        source.loginCheckJs = "({body:function(){return checked(result.body())},code:function(){return result.code()},url:function(){return result.url()}})"
        let client = ReplayHttpClient()
        await enqueue(client, path: "/search", body: "<a href='/book'>OLD</a>")
        await enqueue(client, path: "/explore", body: "<a href='/book'>OLD</a>")
        await enqueue(client, path: "/book", body: "<h1>OLD</h1>")
        await enqueue(client, path: "/toc", body: "<a href='/chapter'>OLD</a>")
        await enqueue(client, path: "/chapter", body: "<p>OLD</p>")
        let web = WebBook(source: source, client: client)
        let search = try await web.search(key: "x")
        let explore = try await web.explore(url: "/explore")
        XCTAssertEqual(search.first?.name, "NEW")
        XCTAssertEqual(explore.first?.name, "NEW")
        var book = Book(now: 0)
        book.bookUrl = "https://flow.test/book"
        book.origin = "https://flow.test"
        book = try await web.bookInfo(book)
        XCTAssertEqual(book.name, "NEW")
        book.tocUrl = "https://flow.test/toc"
        let chapters = try await web.chapterList(book: &book)
        XCTAssertEqual(chapters.first?.title, "NEW")
        let content = try await web.content(book: book, chapter: XCTUnwrap(chapters.first))
        XCTAssertTrue(content.rawContent.contains("NEW"))
    }

    func testLoginCheckCanRecoverNetworkAndHTTPFailures() async throws {
        for transportError in [false, true] {
            var source = source()
            source.loginCheckJs = "if(result.code()!==500) throw 'expected failure'; ({body:function(){return '<a href=\"/book\">Recovered</a>'},code:function(){return 200},url:function(){return result.url()}})"
            let client = ReplayHttpClient()
            if transportError { await client.enqueue(url: URL(string: "https://flow.test/search")!, error: URLError(.timedOut)) }
            else { await enqueue(client, path: "/search", body: "failure", status: 500) }
            let results = try await WebBook(source: source, client: client).search(key: "x")
            XCTAssertEqual(results.first?.name, "Recovered")
        }
    }

    func testFailedRecoveryPreservesOriginalErrorAndCancellation() async throws {
        for check in ["result", "throw 'secondary failure'"] {
            var source = source(); source.loginCheckJs = check
            let client = ReplayHttpClient()
            await client.enqueue(url: URL(string: "https://flow.test/search")!, error: URLError(.timedOut))
            do { _ = try await WebBook(source: source, client: client).search(key: "x"); XCTFail("Expected original failure") }
            catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        }
        var source = source(); source.loginCheckJs = "java.ajax('https://flow.test/retry');result"
        let client = ReplayHttpClient()
        await client.enqueue(url: URL(string: "https://flow.test/search")!, error: CancellationError())
        do { _ = try await WebBook(source: source, client: client).search(key: "x"); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testSessionLoginCheckRunsOnce() async throws {
        var source = source()
        source.loginCheckJs = "source.setVariable(String(Number(source.getVariable()||0)+1));result"
        let database = try AppDatabase.inMemory()
        let client = ReplayHttpClient()
        await enqueue(client, path: "/search", body: "<a href='/book'>Book</a>")
        let web = WebBook(source: source, client: SourceLoginHttpClient(database: database, underlying: client))
        _ = try await web.search(key: "x")
        let value = try SourceStateRepository(database: database).value(source: "https://flow.test", key: "variable")
        XCTAssertEqual(value, "1")
    }

    func testSearchInfoAndTocReuseSingleResponseWithoutSerializingHTML() async throws {
        var source = source()
        source.searchUrl = "/book"
        source.ruleSearch?.bookList = "class.missing"
        let client = ReplayHttpClient()
        await enqueue(client, path: "/book", body: "<h1>Book</h1><a href='/chapter'>Chapter</a>")
        let web = WebBook(source: source, client: client)
        let results = try await web.search(key: "x")
        let search = try XCTUnwrap(results.first)
        XCTAssertNotNil(search.infoHtml)
        var book = try await web.bookInfo(search)
        XCTAssertNotNil(book.tocHtml)
        let chapters = try await web.chapterList(book: &book)
        XCTAssertEqual(chapters.map(\.title), ["Chapter"])
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
        for data in [try JSONEncoder().encode(search), try JSONEncoder().encode(book)] {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNil(object["infoHtml"])
            XCTAssertNil(object["tocHtml"])
        }
    }

    func testDifferentTocURLDoesNotUseDetailsHTML() async throws {
        let client = ReplayHttpClient()
        await enqueue(client, path: "/toc", body: "<a href='/chapter'>Actual</a>")
        var book = Book(now: 0)
        book.origin = "https://flow.test"; book.bookUrl = "https://flow.test/book"; book.tocUrl = "https://flow.test/toc"
        book.tocHtml = "<a href='/wrong'>Wrong</a>"
        let chapters = try await WebBook(source: source(), client: client).chapterList(book: &book)
        XCTAssertEqual(chapters.map(\.title), ["Actual"])
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testURLDeduplicationKeepsFirstSearchAndLastChapter() async throws {
        let html = "<a href='/same'>A</a><a href='/same'>A</a><a href='/same'>B</a>"
        let results = try await BookList.analyze(source: source(), body: html, baseURL: "https://flow.test/search")
        XCTAssertEqual(results.map(\.name), ["A"])
        let client = ReplayHttpClient()
        await enqueue(client, path: "/toc", body: html)
        var book = Book(now: 0)
        book.origin = "https://flow.test"; book.bookUrl = "https://flow.test/book"; book.tocUrl = "https://flow.test/toc"
        let chapters = try await WebBook(source: source(), client: client).chapterList(book: &book)
        XCTAssertEqual(chapters.map(\.title), ["B"])
        XCTAssertEqual(chapters.map(\.index), [0])
    }

}
