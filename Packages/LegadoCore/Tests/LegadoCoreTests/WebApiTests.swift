import XCTest
@testable import LegadoCore

final class WebApiTests: XCTestCase {
    func testHTTPParsingAndFraming() throws {
        let prefix = "POST /saveBook?url=a%2Bb&x=hello+world&x=two HTTP/1.1\r\nHost: localhost\r\nContent-Length: 6\r\n\r\n"
        XCTAssertNil(try WebHttpRequest.parse(Data((prefix + "你").utf8)))
        let request = try XCTUnwrap(WebHttpRequest.parse(Data((prefix + "你好").utf8)))
        XCTAssertEqual(request.query["url"], ["a+b"])
        XCTAssertEqual(request.query["x"], ["hello world", "two"])
        XCTAssertEqual(request.body, Data("你好".utf8))
        for raw in ["GET / HTTP/1.1\r\nContent-Length: -1\r\n\r\n", "GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n", "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"] {
            XCTAssertThrowsError(try WebHttpRequest.parse(Data(raw.utf8)))
        }
        let response = WebHttpResponse(status: 200, contentType: "text/plain", body: Data("你好".utf8))
        XCTAssertTrue(String(decoding: response.encoded(), as: UTF8.self).contains("Content-Length: 6\r\n"))
    }

    func testRoutesAndPage() async throws {
        let router = HttpRouter(api: WebApi(database: try .inMemory()))
        let home = await router.handle(WebHttpRequest(method: "GET", target: "/"))
        XCTAssertEqual(home.status, 200)
        XCTAssertTrue(String(decoding: home.body, as: UTF8.self).contains("getBookshelf"))
        let missing = await router.handle(WebHttpRequest(method: "GET", target: "/missing"))
        XCTAssertEqual(missing.status, 404)
        let wrongMethod = await router.handle(WebHttpRequest(method: "GET", target: "/saveBook"))
        XCTAssertEqual(wrongMethod.status, 405)
    }

    func testBooksControllerSuccessAndFailure() async throws {
        let api = WebApi(database: try .inMemory())
        let empty = try await call(api, "/getBookshelf")
        XCTAssertEqual(empty["isSuccess"] as? Bool, false)
        XCTAssertEqual(empty["errorMsg"] as? String, "还没有添加小说")
        let saved = try await call(api, "/saveBook", body: #"{"bookUrl":"book","name":"小说","author":"作者"}"#)
        XCTAssertEqual(saved["data"] as? String, "")
        let shelf = try await call(api, "/getBookshelf")
        XCTAssertEqual((shelf["data"] as? [[String: Any]])?.first?["bookUrl"] as? String, "book")
        let bad = try await call(api, "/getBookContent?url=book")
        XCTAssertEqual(bad["errorMsg"] as? String, "参数index不能为空, 请指定目录序号")
        let deleted = try await call(api, "/deleteBook", body: #"{"bookUrl":"book"}"#)
        XCTAssertEqual(deleted["isSuccess"] as? Bool, true)
    }

    func testSourcesNestedRulesAndFailure() async throws {
        let api = WebApi(database: try .inMemory())
        let empty = try await call(api, "/getBookSources")
        XCTAssertEqual(empty["errorMsg"] as? String, "设备源列表为空")
        let saved = try await call(api, "/saveBookSource", body: #"{"bookSourceUrl":"source","bookSourceName":"书源","ruleSearch":{"name":"h1"}}"#)
        XCTAssertEqual(saved["isSuccess"] as? Bool, true)
        let source = try await call(api, "/getBookSource?url=source")
        let data = source["data"] as? [String: Any]
        XCTAssertEqual((data?["ruleSearch"] as? [String: Any])?["name"] as? String, "h1")
        let bad = try await call(api, "/saveBookSource", body: "{}")
        XCTAssertEqual(bad["errorMsg"] as? String, "源名称和URL不能为空")
        let deleted = try await call(api, "/deleteBookSources", body: #"[{"bookSourceUrl":"source"}]"#)
        XCTAssertEqual(deleted["data"] as? String, "已执行")
    }

    func testReplaceRulesUseStringDataAndAndroidOrder() async throws {
        let database = try AppDatabase.inMemory()
        var row = ReplaceRuleRow(); row.id = 12; row.name = "rule"; row.order = 7
        try await ReplaceRuleRepository(database: database).insert(row)
        let result = try await call(WebApi(database: database), "/getReplaceRules")
        let json = try XCTUnwrap(result["data"] as? String)
        let rules = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        XCTAssertEqual(rules?.first?["order"] as? Int, 7)
        XCTAssertNil(rules?.first?["sortOrder"])
        let failure = try await call(WebApi(database: database), "/saveReplaceRule", body: "null")
        XCTAssertEqual(failure["isSuccess"] as? Bool, false)
    }

    func testRssControllerSuccessAndFailure() async throws {
        let api = WebApi(database: try .inMemory())
        let empty = try await call(api, "/getRssSources")
        XCTAssertEqual(empty["errorMsg"] as? String, "源列表为空")
        let saved = try await call(api, "/saveRssSource", body: #"{"sourceUrl":"rss","sourceName":"订阅"}"#)
        XCTAssertEqual(saved["isSuccess"] as? Bool, true)
        let source = try await call(api, "/getRssSource?url=rss")
        XCTAssertEqual((source["data"] as? [String: Any])?["sourceName"] as? String, "订阅")
        let deleted = try await call(api, "/deleteRssSources", body: #"[{"sourceUrl":"rss"}]"#)
        XCTAssertEqual(deleted["data"] as? String, "已执行")
    }

    func testSavingExistingBookPreservesChapters() async throws {
        let database = try AppDatabase.inMemory()
        var book = BookRow(); book.bookUrl = "book"; book.name = "小说"
        try await BookshelfRepository(database: database).insert(book)
        var chapter = BookChapterRow(); chapter.bookUrl = "book"; chapter.url = "chapter"; chapter.title = "一"
        try await ChapterRepository(database: database).insert(chapter)
        let api = WebApi(database: database)
        _ = try await call(api, "/saveBook", body: #"{"bookUrl":"book","name":"小说"}"#)
        let remaining = try await ChapterRepository(database: database).list(bookUrl: "book")
        XCTAssertEqual(remaining.count, 1)
        let toc = try await call(api, "/getChapterList?url=book")
        XCTAssertEqual((toc["data"] as? [[String: Any]])?.first?["index"] as? Int, 0)
    }

    func testReplacePreviewAndBatchSources() async throws {
        let api = WebApi(database: try .inMemory())
        let preview = try await call(api, "/testReplaceRule", body: #"{"rule":{"pattern":"a","replacement":"b","isRegex":false},"text":"cat"}"#)
        XCTAssertEqual(preview["data"] as? String, "cbt")
        let sources = try await call(api, "/saveBookSources", body: #"[{"bookSourceUrl":"ok","bookSourceName":"有效"},{"bookSourceUrl":"bad"}]"#)
        XCTAssertEqual((sources["data"] as? [[String: Any]])?.count, 1)
        let rss = try await call(api, "/saveRssSources", body: #"[{"sourceUrl":"rss","sourceName":"订阅"},{"sourceUrl":"bad"}]"#)
        XCTAssertEqual((rss["data"] as? [[String: Any]])?.count, 1)
    }

    func testContentUsesInjectedClient() async throws {
        let database = try AppDatabase.inMemory()
        var book = BookRow(); book.bookUrl = "https://example.invalid/book"; book.name = "小说"; book.origin = "source"
        try await BookshelfRepository(database: database).insert(book)
        var chapter = BookChapterRow(); chapter.bookUrl = book.bookUrl; chapter.url = "https://example.invalid/chapter"; chapter.title = "第一章"
        try await ChapterRepository(database: database).insert(chapter)
        let api = WebApi(database: database, client: WebContentClient())
        _ = try await call(api, "/saveBookSource", body: #"{"bookSourceUrl":"source","bookSourceName":"源","ruleContent":{"content":"p@text"}}"#)
        let result = try await call(api, "/getBookContent?url=https%3A%2F%2Fexample.invalid%2Fbook&index=0")
        XCTAssertEqual(result["isSuccess"] as? Bool, true)
        XCTAssertTrue((result["data"] as? String)?.contains("正文") == true)
        XCTAssertFalse((result["data"] as? String)?.contains("第一章") == true)
    }

    private func call(_ api: WebApi, _ target: String, body: String? = nil) async throws -> [String: Any] {
        let response = await HttpRouter(api: api, token: { "test" }).handle(WebHttpRequest(method: body == nil ? "GET" : "POST", target: target, headers: ["x-legado-token": "test"], body: Data((body ?? "").utf8)))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }
}

private struct WebContentClient: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        HttpResponse(status: 200, body: Data("<p>正文</p>".utf8), finalURL: request.url)
    }
}
