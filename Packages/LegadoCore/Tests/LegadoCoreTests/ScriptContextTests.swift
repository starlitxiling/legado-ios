import XCTest
@testable import LegadoCore

final class ScriptContextTests: XCTestCase {
    private let base = "https://example.invalid"

    private func source() -> BookSource {
        var source = BookSource()
        source.bookSourceUrl = base
        source.bookSourceName = "Source"
        return source
    }

    private func enqueue(_ client: ReplayHttpClient, _ path: String, _ body: String) async {
        let url = URL(string: base + path)!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data(body.utf8), finalURL: url))
    }

    func testURLVariablesAndInfoMapSurviveScriptPhases() throws {
        let executor = try AnalyzeUrlExecutor("@js:java.put('k', 'v'); '/{{java.get(\"k\")}}/{{infoMap.get(\"page\")}}'",
            engine: JsEngine(baseUrl: base), bindings: ["page": 3, "infoMap": ["page": 3]])
        XCTAssertEqual(executor.url, base + "/v/3")
    }

    func testEntityFieldsAndChapterVariables() throws {
        var book = Book(now: 0)
        book.name = "Book"; book.author = "Author"; book.variable = #"{"shared":"book"}"#
        var chapter = BookChapter()
        chapter.title = "Chapter"; chapter.index = 7; chapter.variable = #"{"shared":"chapter"}"#
        let context = try WebBookContext(source: source(), client: ReplayHttpClient(), book: book)
        let parser = try context.parser("body", baseURL: base, chapter: chapter, nextChapterURL: "/next")
        XCTAssertEqual(try parser.getString("@js:book.author + '|' + chapter.index + '|' + source.bookSourceUrl"), "Author|7|" + base)
        XCTAssertEqual(try parser.getString("@js:book.putVariable('custom','saved');book.getVariable('custom')+'|'+chapter.getVariable('shared')"), "saved|chapter")
        XCTAssertEqual(try parser.getString("@js:java.get('shared') + '|' + JSON.parse(chapter.variable).shared + '|' + nextChapterUrl"), "chapter|chapter|/next")
        XCTAssertEqual(try parser.getString("@js:book.author='changed'; chapter.index=99; source.bookSourceUrl='changed'; book.author+'|'+chapter.index+'|'+source.getKey()"), "Author|7|" + base)
    }

    func testSourceMethodsPersistAcrossParserSessions() throws {
        let context = try WebBookContext(source: source(), client: ReplayHttpClient())
        let first = try context.parser("", baseURL: base)
        XCTAssertEqual(try first.getString("@js:source.setVariable('value'); source.putLoginHeader(JSON.stringify({Token:'token'})); source.putLoginInfo(JSON.stringify({user:'reader'})); source.getKey()"), base)
        let second = try context.parser("", baseURL: base)
        XCTAssertEqual(try second.getString("@js:source.getVariable()+'|'+JSON.parse(source.getLoginHeader()).Token+'|'+JSON.parse(source.getLoginInfo()).user"), "value|token|reader")
        XCTAssertEqual(try second.getString("@js:source.getVariable()"), "value")
    }

    func testSearchVariablesReachDetailsAndTocURL() async throws {
        var source = source()
        source.searchUrl = "@js:java.put('k','v'); '/search'"
        source.ruleSearch = SearchRule()
        source.ruleSearch?.bookList = "tag.a"
        source.ruleSearch?.name = "text"
        source.ruleSearch?.bookUrl = "href"
        source.ruleBookInfo = BookInfoRule()
        source.ruleBookInfo?.tocUrl = "@js:'/toc/{{java.get(\"k\")}}/{{java.get(\"detail\")}}'"
        source.ruleBookInfo?.intro = "@js:java.put('detail','ok'); String(fromBookInfo)+'|'+String(isFromBookInfo)"
        source.ruleToc = TocRule()
        source.ruleToc?.chapterList = "tag.a"
        source.ruleToc?.chapterName = "text"
        source.ruleToc?.chapterUrl = "href"
        let client = ReplayHttpClient()
        await enqueue(client, "/search", "<a href='/book'>Book</a>")
        await enqueue(client, "/book", "details")
        await enqueue(client, "/toc/v/ok", "<a href='/chapter'>Chapter</a>")
        let web = WebBook(source: source, client: client)
        let results = try await web.search(key: "Book")
        var book = try await web.bookInfo(XCTUnwrap(results.first))
        XCTAssertEqual(book.intro, "true|true")
        let chapters = try await web.chapterList(book: &book)
        XCTAssertEqual(chapters.first?.title, "Chapter")
    }

    func testContentURLAndRulesShareChapterVariables() async throws {
        var source = source()
        source.ruleContent = ContentRule()
        source.ruleContent?.content = "@js:java.put('saved','yes'); java.get('initial')+'|'+java.get('request')"
        source.ruleContent?.title = "@js:java.get('saved')"
        var book = Book(now: 0); book.name = "Book"
        var chapter = BookChapter()
        chapter.title = "Chapter"; chapter.variable = #"{"initial":"seed"}"#
        chapter.url = base + #"/read,{"js":"java.put('request','url');result"}"#
        let client = ReplayHttpClient()
        await enqueue(client, "/read", "body")
        let result = try await WebBook(source: source, client: client).content(book: book, chapter: chapter)
        XCTAssertEqual(result.rawContent, "seed|url")
        XCTAssertEqual(result.chapter.title, "yes")
        let variables = try JSONDecoder().decode([String: String].self, from: Data(XCTUnwrap(result.chapter.variable).utf8))
        XCTAssertEqual(variables["saved"], "yes")
        XCTAssertEqual(variables["request"], "url")
    }

    func testTocVariablesStayWithTheirChapterAndFormatSeesFullContext() async throws {
        var source = source()
        source.ruleToc = TocRule()
        source.ruleToc?.chapterList = "tag.a"
        source.ruleToc?.chapterName = "text@js:java.put('token',result); result"
        source.ruleToc?.chapterUrl = "@js:'/'+java.get('token')"
        source.ruleToc?.formatJs = "chapters.length+':'+book.author+':'+chapter.index+':'+JSON.parse(chapter.variable).token"
        let client = ReplayHttpClient()
        await enqueue(client, "/toc", "<a>A</a><a>B</a>")
        var book = Book(now: 0); book.tocUrl = base + "/toc"; book.author = "Author"
        let chapters = try await WebBook(source: source, client: client).chapterList(book: &book)
        XCTAssertEqual(chapters.map(\.title), ["2:Author:0:A", "2:Author:1:B"])
        XCTAssertEqual(chapters.map(\.url), ["/A", "/B"])
    }

    func testRssArticleAndURLVariablesAreAvailableDuringParsing() async throws {
        var source = RssSource(sourceUrl: base, sourceName: "Feed")
        source.ruleArticles = "tag.a"
        source.ruleTitle = "text"
        source.rulePubDate = "@js:rssArticle.title+'|'+rssArticle.sort+'|'+java.get('request')"
        source.ruleLink = "href"
        source.ruleContent = "@js:rssArticle.title+'|'+java.get('request')"
        let client = ReplayHttpClient()
        await enqueue(client, "/feed", "<a href='/article'>Article</a>")
        await enqueue(client, "/article", "body")
        let service = RssService(client: client)
        let page = try await service.articles(source: source, sort: "News", url: "@js:java.put('request','rss'); '/feed'")
        let article = try XCTUnwrap(page.articles.first)
        XCTAssertEqual(article.pubDate, "Article|News|rss")
        let content = try await service.content(article: article, source: source)
        XCTAssertEqual(content, .html("Article|rss", baseURL: base + "/article"))
    }

    func testURLExtraParamsOverrideVariablesWithoutChangingStorage() throws {
        let variables = RuleVariableStore(["key": "saved"])
        let parser = AnalyzeRule(ruleData: variables)
        let executor = try AnalyzeUrlExecutor("/{{java.get('key')}}/{{page}}",
            engine: JsEngine(baseUrl: base), bindings: ["extraParams": ["key": "request", "page": "2"]], context: parser)
        XCTAssertEqual(executor.url, base + "/request/2")
        XCTAssertEqual(variables.value(for: "key"), "saved")
        XCTAssertEqual(try parser.get("key"), "saved")
    }

    func testTypedBindingsShareSourceVariablesWithSourceMethods() throws {
        let binding = JsSourceBinding(source())
        let parser = AnalyzeRule(content: "", engines: [.js: JsEngine()], source: binding)
        XCTAssertEqual(try parser.getString("@js:source.put('k','source');java.get('k')"), "source")
        XCTAssertEqual(try parser.getString("@js:java.put('k','host');source.get('k')"), "host")
        XCTAssertEqual(try parser.getString("@get:{k}"), "host")
    }

    func testPersistentSourceVariablesAreSharedWithRuleFallback() throws {
        let database = try AppDatabase.inMemory()
        let client = SourceSessionHttpClient(source: source(), database: database,
            client: ReplayHttpClient(), secrets: MemorySourceSecretStore())
        let context = try WebBookContext(source: source(), client: client)
        let first = try context.parser("", baseURL: base)
        XCTAssertEqual(try first.getString("@js:source.put('k','saved');java.get('k')"), "saved")
        let restored = try WebBookContext(source: source(), client: client)
        XCTAssertEqual(try restored.parser("", baseURL: base).getString("@get:{k}"), "saved")
    }

    func testInvalidEntityVariablesFailWithDiagnostic() {
        var book = Book(now: 0); book.variable = "invalid"
        XCTAssertThrowsError(try JsBookBinding(book)) {
            XCTAssertTrue($0.localizedDescription.contains("entity variable JSON"))
        }
    }

    func testRuleSessionDoesNotRetainItsParser() throws {
        weak var released: AnalyzeRule?
        try autoreleasepool {
            let engine = JsEngine()
            let parser = AnalyzeRule(content: "", engines: [.js: engine], ruleData: RuleVariableStore())
            released = parser
            XCTAssertEqual(try parser.getString("@js:java.put('k','v');java.get('k')"), "v")
        }
        XCTAssertNil(released)
    }
}
