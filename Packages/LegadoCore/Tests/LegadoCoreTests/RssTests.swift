import XCTest
@testable import LegadoCore

final class RssTests: XCTestCase {
    func testSourceDefaultsColumnsAndImportShapes() throws {
        let source = try GsonJSONDecoder().decode(RssSource.self, from: Data(#"{"sourceUrl":"https://feed.test","sortUrl":"新闻::/news\n技术::/tech"}"#.utf8))
        XCTAssertTrue(source.enabled)
        XCTAssertTrue(source.enableJs)
        XCTAssertTrue(source.loadWithBaseUrl)
        XCTAssertEqual(source.columns.map(\.name), ["新闻", "技术"])
        XCTAssertEqual(source.columns.map(\.url), ["https://feed.test/news", "https://feed.test/tech"])
        let importer = SourceImporter()
        XCTAssertEqual(importer.parseRssSources(#"{"sourceUrl":"https://feed.test"}"#), .sources([RssSource(sourceUrl: "https://feed.test")]))
        XCTAssertEqual(importer.parseRssSources(#"[{"sourceUrl":"https://feed.test"}]"#), .sources([RssSource(sourceUrl: "https://feed.test")]))
        XCTAssertEqual(importer.parseRssSources(#"["https://feed.test"]"#), .urls(["https://feed.test"]))
        XCTAssertEqual(importer.parseRssSources(#"{"sourceUrls":["https://feed.test"]}"#), .urls(["https://feed.test"]))
        XCTAssertEqual(importer.parseRssSources(#"[{}]"#), .invalid)
    }

    func testRSSXML() throws {
        let xml = """
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel><title>Feed</title><item><title>One</title><link>../one</link><pubDate>Yesterday</pubDate><description><![CDATA[<p>Summary</p>]]></description><content:encoded><![CDATA[<b>Body</b>]]></content:encoded><enclosure type="image/png" url="/cover.png"/></item></channel></rss>
        """
        let page = try RssParser().parse(xml, source: RssSource(sourceUrl: "https://feed.test/rss"), sort: "News", baseURL: "https://feed.test/rss/feed")
        XCTAssertEqual(page.articles.count, 1)
        XCTAssertEqual(page.articles.first?.link, "https://feed.test/one")
        XCTAssertEqual(page.articles.first?.content, "<b>Body</b>")
        XCTAssertEqual(page.articles.first?.image, "https://feed.test/cover.png")
        XCTAssertNil(page.nextPageURL)
    }

    func testAtomXML() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Feed</title><entry><title>Atom</title><link rel="self" href="/api/1"/><link rel="alternate" href="/one"/><updated>2026-01-02</updated><summary>Summary</summary><content type="html">&lt;p&gt;Body&lt;/p&gt;</content></entry></feed>
        """
        let page = try RssParser().parse(xml, source: RssSource(sourceUrl: "https://feed.test"), baseURL: "https://feed.test/rss")
        XCTAssertEqual(page.articles.first?.title, "Atom")
        XCTAssertEqual(page.articles.first?.link, "https://feed.test/one")
        XCTAssertEqual(page.articles.first?.content, "<p>Body</p>")
        XCTAssertEqual(page.articles.first?.pubDate, "2026-01-02")
        XCTAssertThrowsError(try RssParser().parse("<rss>", source: RssSource(), baseURL: "https://feed.test"))
    }

    func testRulePaginationDeduplicates() async throws {
        var source = RssSource(sourceUrl: "https://feed.test/list")
        source.ruleArticles = "class.item"; source.ruleTitle = "tag.a@text"
        source.ruleLink = "tag.a@href"; source.ruleNextPage = "class.next@href"
        let client = ReplayHttpClient()
        let first = URL(string: source.sourceUrl)!
        let second = URL(string: "https://feed.test/page2")!
        await client.enqueue(url: first, response: .init(status: 200, body: Data(#"<div class="item"><a href="/one">One</a></div><a class="next" href="/page2">Next</a>"#.utf8), finalURL: first))
        await client.enqueue(url: second, response: .init(status: 200, body: Data(#"<div class="item"><a href="/one">One</a></div><div class="item"><a href="/two">Two</a></div>"#.utf8), finalURL: second))
        let service = RssService(client: client)
        let a = try await service.articles(source: source, sort: "News", url: source.sourceUrl)
        let b = try await service.articles(source: source, sort: "News", url: try XCTUnwrap(a.nextPageURL), page: 2, existing: a.articles)
        XCTAssertEqual(b.articles.map(\.title), ["Two"])
        XCTAssertNil(b.nextPageURL)
    }

    func testFavoritesAndReadRoundTrip() async throws {
        let repository = RssRepository(database: try .inMemory())
        var article = RssArticle(origin: "feed", link: "https://feed.test/one", title: "One")
        article.content = "Body"; article.sort = "News"
        try await repository.saveArticles([article])
        try await repository.setStar(article, starred: true, time: 42)
        let stars = try await repository.stars()
        XCTAssertEqual(stars.first?.starTime, 42)
        XCTAssertEqual(stars.first?.article.content, "Body")
        try await repository.markRead(article, time: 43)
        let loaded = try await repository.articles(origin: "feed", sort: "News")
        XCTAssertEqual(loaded.first?.read, true)
        try await repository.setStar(article, starred: false, time: 44)
        let empty = try await repository.stars()
        XCTAssertTrue(empty.isEmpty)
    }
}

extension RssTests {
    func testBackupSourcesBeforeStars() async throws {
        let database = try AppDatabase.inMemory()
        let archive = BackupReviewTests.archive([
            "rssSources.json": #"[{"sourceUrl":"https://feed.test","sourceName":"Feed","style":"body{color:red}"}]"#,
            "rssStar.json": #"[{"origin":"https://feed.test","link":"https://feed.test/one","title":"One","starTime":42,"content":"body"}]"#
        ])
        let report = try await BackupImporter(database: database, localDeviceID: "test").importArchive(archive)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(report.importedFiles, ["rssSources.json", "rssStar.json"])
        let repository = RssRepository(database: database)
        let sources = try await repository.sources()
        let stars = try await repository.stars()
        XCTAssertEqual(sources.first?.style, "body{color:red}")
        XCTAssertEqual(stars.first?.content, "body")
    }

    func testContentRuleAndURLAndBaseURL() async throws {
        let client = ReplayHttpClient()
        var source = RssSource(sourceUrl: "https://feed.test")
        source.ruleContent = "tag.article@html"
        var article = RssArticle(origin: source.sourceUrl, link: "https://feed.test/one")
        let url = URL(string: article.link)!
        await client.enqueue(url: url, response: .init(status: 200, body: Data("<article><b>Body</b></article>".utf8), finalURL: url))
        let service = RssService(client: client)
        let result = try await service.content(article: article, source: source)
        XCTAssertEqual(result, .html("<article>\n <b>Body</b>\n</article>", baseURL: article.link))
        article.content = "stale"; article.description = "https://feed.test/direct"
        let direct = try await service.content(article: article, source: source)
        XCTAssertEqual(direct, .url("https://feed.test/direct"))
        source.loadWithBaseUrl = false; article.description = "Inline"
        let inline = try await service.content(article: article, source: source)
        XCTAssertEqual(inline, .html("Inline", baseURL: nil))
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testPageRuleAndReverse() throws {
        var source = RssSource(sourceUrl: "https://feed.test")
        source.ruleArticles = "-tag.a"; source.ruleTitle = "text"; source.ruleLink = "href"; source.ruleNextPage = "page"
        let result = try RssParser().parse(#"<a href="/one">One</a><a href="/two">Two</a>"#, source: source, baseURL: "https://feed.test/list")
        XCTAssertEqual(result.articles.map(\.title), ["Two", "One"])
        XCTAssertEqual(result.nextPageURL, "https://feed.test/list")
    }

    func testResourcePoliciesAndNavigationScript() throws {
        var source = RssSource()
        source.contentWhitelist = "https://allowed.test/,https://image[.]test/.*"
        var policy = RssWebPolicy(source: source)
        XCTAssertTrue(policy.allowsResource("https://allowed.test/article"))
        XCTAssertTrue(policy.allowsResource("https://image.test/a.jpg"))
        XCTAssertFalse(policy.allowsResource("https://tracker.test/a"))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(policy.contentRulesJSON().utf8)))
        source.contentBlacklist = "https://tracker.test"
        source.shouldOverrideUrlLoading = "url.indexOf('blocked') >= 0"
        policy = RssWebPolicy(source: source)
        XCTAssertTrue(policy.allowsResource("https://other.test"))
        XCTAssertFalse(policy.allowsResource("https://tracker.test/a"))
        XCTAssertTrue(try policy.shouldOverride("https://blocked.test", client: ReplayHttpClient()))
        XCTAssertFalse(try policy.shouldOverride("https://other.test", client: ReplayHttpClient()))
    }
}

extension RssTests {
    func testColumnURLKeepsPageTemplateForExecutor() async throws {
        var source = RssSource(sourceUrl: "https://feed.test")
        source.sortUrl = "News::/list?page={{page}}"
        source.ruleArticles = "tag.a"; source.ruleTitle = "text"; source.ruleLink = "href"
        let client = ReplayHttpClient()
        let url = URL(string: "https://feed.test/list?page=2")!
        await client.enqueue(url: url, response: .init(status: 200, body: Data(#"<a href="/one">One</a>"#.utf8), finalURL: url))
        let result = try await RssService(client: client).articles(source: source, sort: "News", url: source.columns[0].url, page: 2)
        XCTAssertEqual(result.articles.first?.title, "One")
    }
    func testXMLContentPreservesXHTMLAndExtractsImage() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Atom</title><link href="/one"/><content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>Body</p><img src="/cover.png"/></div></content></entry></feed>
        """
        let result = try RssParser().parse(xml, source: RssSource(sourceUrl: "https://feed.test"), baseURL: "https://feed.test/feed")
        XCTAssertTrue(result.articles.first?.content?.contains("<p>Body</p>") == true)
        XCTAssertEqual(result.articles.first?.image, "https://feed.test/cover.png")
    }
}

extension RssTests {
    func testSourceRenameKeepsArticlesAndStars() async throws {
        let repository = RssRepository(database: try .inMemory())
        try await repository.saveSources([RssSource(sourceUrl: "old", sourceName: "Old")])
        let article = RssArticle(origin: "old", link: "article", title: "One")
        try await repository.saveArticles([article])
        try await repository.setStar(article, starred: true, time: 10)
        try await repository.renameSource(RssSource(sourceUrl: "new", sourceName: "New"), replacing: "old")
        let sources = try await repository.sources()
        let articles = try await repository.articles(origin: "new", sort: "")
        let stars = try await repository.stars()
        XCTAssertEqual(sources.map(\.sourceUrl), ["new"])
        XCTAssertEqual(articles.first?.title, "One")
        XCTAssertEqual(stars.first?.origin, "new")
    }
}

extension RssTests {
    func testRequestJavaScriptReceivesSource() async throws {
        var source = RssSource(sourceUrl: "https://feed.test")
        source.ruleArticles = "tag.a"; source.ruleTitle = "text"; source.ruleLink = "href"
        let client = ReplayHttpClient()
        let url = URL(string: "https://feed.test/list")!
        await client.enqueue(url: url, response: .init(status: 200, body: Data(#"<a href="/one">One</a>"#.utf8), finalURL: url))
        let result = try await RssService(client: client).articles(source: source, sort: "News", url: "@js:source.sourceUrl + '/list'")
        XCTAssertEqual(result.articles.first?.title, "One")
    }
}

extension RssTests {
    func testReview1ArticleVariablesSurviveParsingAndContent() async throws {
        var source = RssSource(sourceUrl: "https://feed.test")
        source.ruleArticles = "@js:java.put('shared','list'); [result,result]"
        source.ruleTitle = "@js:java.put('own',java.get('own')+'article'); java.get('shared')"
        source.ruleLink = "@js:'https://feed.test/one'"
        source.ruleContent = "@js:java.get('shared') + ':' + java.get('own')"
        let page = try RssParser().parse("<p>One</p>", source: source, baseURL: source.sourceUrl)
        XCTAssertEqual(page.articles.count, 2)
        let article = try XCTUnwrap(page.articles.first)
        XCTAssertEqual(article.title, "list")
        let variables = try JSONDecoder().decode([String: String].self, from: Data((article.variable ?? "{}").utf8))
        XCTAssertEqual(variables["own"], "article")
        let client = ReplayHttpClient()
        let url = URL(string: article.link)!
        await client.enqueue(url: url, response: .init(status: 200, body: Data("body".utf8), finalURL: url))
        let content = try await RssService(client: client).content(article: article, source: source)
        XCTAssertEqual(content, .html("list:article", baseURL: article.link))
    }
    func testReview2ScriptColumnsAndDefaultName() throws {
        var source = RssSource(sourceUrl: "https://feed.test", sourceName: "Feed")
        XCTAssertEqual(source.columns.first?.name, "")
        for script in ["@js:'News::/news&&Tech::/tech'", "<js>'News::/news\\nTech::/tech'</js>"] {
            source.sortUrl = script
            XCTAssertEqual(source.columns.map(\.name), ["News", "Tech"])
        }
        source.sortUrl = "News::/news&&Tech::/tech"
        XCTAssertEqual(source.columns.count, 2)
        source.sortUrl = "@js:throw new Error('bad')"
        XCTAssertEqual(source.columns.first?.name, "")
    }
    func testReview3LoginCheckSuccessAndFailure() async throws {
        for fails in [false, true] {
            let client = ReplayHttpClient()
            var source = RssSource(sourceUrl: "https://feed.test/list")
            source.ruleArticles = "tag.a"; source.ruleTitle = "text"; source.ruleLink = "href"
            source.loginCheckJs = "source.setVariable('checked'); ({body:function(){return '<a href=\"/one\">' + source.getVariable() + '</a>'},code:function(){return 200},url:function(){return 'https://feed.test/list'}})"
            let url = URL(string: source.sourceUrl)!
            if fails { await client.enqueue(url: url, error: URLError(.timedOut)) }
            else { await client.enqueue(url: url, response: .init(status: 200, body: Data("<a href='/old'>unchecked</a>".utf8), finalURL: url)) }
            do {
                let page = try await RssService(client: client).articles(source: source, sort: "", url: source.sourceUrl)
                XCTAssertEqual(page.articles.first?.title, "checked")
            } catch { XCTFail("login check failed: \(error)") }
        }
    }
    func testReview5ReadEntryUsesDescriptionThenRuleThenURL() async throws {
        var source = RssSource(sourceUrl: "https://feed.test")
        source.ruleContent = "tag.p@text"
        var article = RssArticle(origin: source.sourceUrl, link: "https://feed.test/one")
        article.content = "stale"; article.description = "description"
        let client = ReplayHttpClient()
        let service = RssService(client: client)
        var result = try await service.content(article: article, source: source)
        XCTAssertEqual(result, .html("description", baseURL: article.link))
        article.description = " \n "
        let url = URL(string: article.link)!
        await client.enqueue(url: url, response: .init(status: 200, body: Data("<p>fresh</p>".utf8), finalURL: url))
        result = try await service.content(article: article, source: source)
        XCTAssertEqual(result, .html("fresh", baseURL: article.link))
        source.ruleContent = " \n "
        result = try await service.content(article: article, source: source)
        XCTAssertEqual(result, .url(article.link))
    }
    func testReview6ImageErrorDoesNotDropArticle() throws {
        var source = RssSource(sourceUrl: "https://feed.test")
        source.ruleArticles = "tag.a"; source.ruleTitle = "text"; source.ruleLink = "href"
        source.ruleImage = "@js:throw new Error('image failure')"
        let page = try RssParser().parse("<a href='/one'>One</a>", source: source, baseURL: source.sourceUrl)
        XCTAssertEqual(page.articles.first?.title, "One")
        XCTAssertNil(page.articles.first?.image)
    }
}
