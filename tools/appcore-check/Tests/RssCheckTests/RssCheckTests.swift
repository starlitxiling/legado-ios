import XCTest
import LegadoCore
@testable import RssCheck

@MainActor final class RssCheckTests: XCTestCase {
    func testImportGroupsAndEnableRoundTrip() async throws {
        let repository = RssRepository(database: try .inMemory())
        let client = ReplayHttpClient()
        let model = RssSourceListModel(repository: repository, client: client)
        await model.importText(#"[{"sourceUrl":"https://feed.test","sourceName":"Feed","sourceGroup":"News,Tech"}]"#)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.groups, ["全部", "News", "Tech"])
        model.selectedGroup = "Tech"
        XCTAssertEqual(model.visibleSources.count, 1)
        var source = try XCTUnwrap(model.sources.first)
        source.enabled = false
        try await model.save(source)
        XCTAssertFalse(try XCTUnwrap(model.sources.first).enabled)
        await model.delete(source)
        XCTAssertTrue(model.sources.isEmpty)
    }
    func testImportRemoteURLArray() async throws {
        let client = ReplayHttpClient()
        let url = URL(string: "https://feed.test/sources.json")!
        await client.enqueue(url: url, response: .init(status: 200, body: Data(#"[{"sourceUrl":"https://feed.test/rss"}]"#.utf8), finalURL: url))
        let model = RssSourceListModel(repository: RssRepository(database: try .inMemory()), client: client)
        await model.importText(#"["https://feed.test/sources.json"]"#)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.sources.map(\.sourceUrl), ["https://feed.test/rss"])
    }
    func testReadMarksReadAndFavorites() async throws {
        let repository = RssRepository(database: try .inMemory())
        var article = RssArticle(origin: "https://feed.test", link: "https://feed.test/one", title: "One")
        article.description = "Body"
        let model = RssReadModel(article: article, source: RssSource(sourceUrl: article.origin), repository: repository, client: ReplayHttpClient(), now: { 42 })
        await model.load()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.content, .html("Body", baseURL: article.link))
        let read = try await repository.articles(origin: article.origin, sort: "")
        XCTAssertEqual(read.first?.read, true)
        await model.toggleStar()
        XCTAssertTrue(model.starred)
        await model.toggleStar()
        XCTAssertFalse(model.starred)
    }
}

extension RssCheckTests {
    func testRefreshFailureRetriesWithoutDeduplicatingCachedFirstPage() async throws {
        let repository = RssRepository(database: try .inMemory())
        let client = ReplayHttpClient()
        var source = RssSource(sourceUrl: "https://feed.test/list", sourceName: "Feed")
        source.ruleArticles = "tag.a"; source.ruleTitle = "text"; source.ruleLink = "href"
        var cached = RssArticle(origin: source.sourceUrl, link: "https://feed.test/one", title: "Old")
        cached.sort = ""
        try await repository.saveArticles([cached])
        let url = URL(string: source.sourceUrl)!
        await client.enqueue(url: url, error: URLError(.timedOut))
        await client.enqueue(url: url, response: .init(status: 200, body: Data(#"<a href="/one">Fresh</a>"#.utf8), finalURL: url))
        let model = RssArticlesModel(source: source, repository: repository, client: client)
        await model.refresh()
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.articles.first?.title, "Old")
        await model.loadMore()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.articles.first?.title, "Fresh")
        XCTAssertNil(model.nextURL)
    }
}

extension RssCheckTests {
    func testReview4RefreshRemovesOnlyCurrentPagedColumn() async throws {
        let repository = RssRepository(database: try .inMemory())
        let client = ReplayHttpClient()
        var source = RssSource(sourceUrl: "https://feed.test/list")
        source.sortUrl = "News::https://feed.test/list"
        source.ruleArticles = "tag.a"; source.ruleTitle = "text"; source.ruleLink = "href"; source.ruleNextPage = "PAGE"
        var old = RssArticle(origin: source.sourceUrl, link: "https://feed.test/old", title: "Old"); old.sort = "News"
        var other = old; other.sort = "Other"
        try await repository.saveArticles([old, other])
        let url = URL(string: source.sourceUrl)!
        await client.enqueue(url: url, response: .init(status: 200, body: Data("<a href='/fresh'>Fresh</a>".utf8), finalURL: url))
        let model = RssArticlesModel(source: source, repository: repository, client: client)
        await model.refresh()
        let rows = try await repository.articles(origin: source.sourceUrl, sort: "News")
        let others = try await repository.articles(origin: source.sourceUrl, sort: "Other")
        XCTAssertEqual(rows.map(\.title), ["Fresh"])
        XCTAssertEqual(others.count, 1)
    }
}

extension RssCheckTests {
    func testReview7StartHTMLBeforeColumnsAndSingleURLPrecedence() async throws {
        let repository = RssRepository(database: try .inMemory())
        var source = RssSource(sourceUrl: "https://feed.test")
        source.startHtml = "<h1>Start</h1>"
        XCTAssertEqual(RssSourceDestination(source: source), .startHTML("<h1>Start</h1>"))
        let model = RssReadModel(article: RssArticle(origin: source.sourceUrl, link: source.sourceUrl), source: source,
                                 repository: repository, client: ReplayHttpClient(), startHTML: source.startHtml, now: { 42 })
        await model.load()
        XCTAssertEqual(model.content, .html("<h1>Start</h1>", baseURL: source.sourceUrl))
        XCTAssertNil(model.error)
        await model.toggleStar()
        let stars = try await repository.stars()
        XCTAssertTrue(stars.isEmpty)
        source.singleUrl = true
        XCTAssertEqual(RssSourceDestination(source: source), .singleURL)
        source.singleUrl = false; source.startHtml = " \n "
        XCTAssertEqual(RssSourceDestination(source: source), .articles)
    }
}
