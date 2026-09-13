import XCTest
@testable import LegadoCore

final class WebBookTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/Conformance/fixtures/webbook")

    private func source() throws -> BookSource {
        try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: root.appendingPathComponent("source.json")))
    }

    private func enqueue(_ client: ReplayHttpClient, _ path: String, fixture: String) async throws {
        let url = URL(string: "https://example.invalid" + path)!
        await client.enqueue(url: url, response: HttpResponse(status: 200,
            body: try Data(contentsOf: root.appendingPathComponent(fixture)), finalURL: url))
    }

    func testOfflineJourney() async throws {
        let client = ReplayHttpClient()
        for (path, file) in [("/search?key=demo&page=1", "search.html"), ("/book/1", "info.html"),
                             ("/toc/1", "toc1.html"), ("/toc/2", "toc2.html"),
                             ("/read/1", "content1.html"), ("/read/1-2", "content2.html"),
                             ("/read/1-3", "content3.html")] {
            try await enqueue(client, path, fixture: file)
        }
        var replacement = ReplaceRule(now: 1)
        replacement.pattern = "海风"; replacement.replacement = "晚风"; replacement.isRegex = false
        let web = WebBook(source: try source(), client: client, replaceRules: [replacement])
        let results = try await web.search(key: "demo")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "航海记")
        XCTAssertEqual(results[0].author, "林舟")
        XCTAssertEqual(results[0].bookUrl, "https://example.invalid/book/1")
        XCTAssertEqual(results[0].coverUrl, "https://example.invalid/cover.jpg")
        XCTAssertEqual(results[0].origin, "https://example.invalid")
        XCTAssertEqual(results[0].originName, "离线书源")
        XCTAssertEqual(results[0].kind, "小说,旅行")
        var book = try await web.bookInfo(results[0])
        XCTAssertEqual(book.tocUrl, "https://example.invalid/toc/1")
        XCTAssertEqual(book.intro, "一段合成的航海故事。")
        XCTAssertEqual(book.latestChapterTitle, "归来")
        let chapters = try await web.chapterList(book: &book)
        XCTAssertEqual(chapters.map(\.title), ["启航", "归来"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
        XCTAssertTrue(chapters[1].isVip)
        XCTAssertTrue(chapters[1].isPay)
        XCTAssertEqual(chapters[1].tag, "新版")
        XCTAssertEqual(book.totalChapterNum, 2)
        let result = try await web.content(book: book, chapter: chapters[0], nextChapterUrl: chapters[1].url)
        XCTAssertEqual(result.chapter.title, "第一章 启航")
        XCTAssertEqual(result.text, "第一章 启航\n　　晚风吹来。\n　　船离开港口。\n　　星光照亮海面。")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 7)
    }

    func testDiscoveryFallsBackToSearchRules() async throws {
        let client = ReplayHttpClient()
        try await enqueue(client, "/explore", fixture: "search.html")
        let results = try await WebBook(source: source(), client: client).explore(url: "/explore")
        XCTAssertEqual(results.map(\.name), ["航海记"])
    }

    func testFilterAndEmptyResults() async throws {
        let client = ReplayHttpClient()
        try await enqueue(client, "/search?key=demo&page=1", fixture: "search.html")
        let results = try await WebBook(source: source(), client: client).search(key: "demo", filter: { _, author, _ in author == "其他" })
        XCTAssertTrue(results.isEmpty)
        let empty = try await BookList.analyze(source: source(), body: "<html></html>", baseURL: "https://example.invalid/search")
        XCTAssertTrue(empty.isEmpty)
    }

    func testRequestFailurePropagates() async throws {
        let client = ReplayHttpClient()
        await client.enqueue(url: URL(string: "https://example.invalid/search?key=demo&page=1")!, error: URLError(.timedOut))
        do {
            _ = try await WebBook(source: source(), client: client).search(key: "demo")
            XCTFail("请求必须失败")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
    }

    func testReplacementScopesAndCaptures() throws {
        var rule = ReplaceRule(now: 1)
        rule.pattern = "(海)(风)"; rule.replacement = "$2$1"; rule.scope = "航海记"
        var book = Book(now: 0); book.name = "航海记"; book.origin = "https://example.invalid"
        var chapter = BookChapter(); chapter.title = "海风"
        let processor = ContentProcessor(rules: [rule])
        XCTAssertEqual(try processor.getContent(book: book, chapter: chapter, content: "海风\n海风来了").text, "海风\n　　风海来了")
        book.name = "其他"
        XCTAssertEqual(try processor.getContent(book: book, chapter: chapter, content: "海风来了", includeTitle: false).text, "　　海风来了")
    }

    func testSingleBookAndURLPattern() async throws {
        var source = try source()
        source.ruleSearch?.bookList = nil
        let html = try String(contentsOf: root.appendingPathComponent("info.html"), encoding: .utf8)
        let single = try await BookList.analyze(source: source, body: html, baseURL: "https://example.invalid/book/1")
        XCTAssertEqual(single.map(\.name), ["航海记"])
        source.ruleSearch?.bookList = "class.book"
        source.bookUrlPattern = "https://example\\.invalid/book/\\d+"
        let matched = try await BookList.analyze(source: source, body: html, baseURL: "https://example.invalid/book/1")
        XCTAssertEqual(matched.map(\.tocUrl), ["https://example.invalid/toc/1"])
        let unmatched = try await BookList.analyze(source: source, body: html, baseURL: "https://example.invalid/search")
        XCTAssertTrue(unmatched.isEmpty)
    }

    func testInfoRenameAndInit() async throws {
        var source = try source()
        source.ruleBookInfo?.`init` = "tag.main"
        source.ruleBookInfo?.canReName = "1"
        var book = Book(now: 0); book.name = "原名"; book.author = "原作者"
        let html = "<h1>错误</h1><main><h1>新名</h1><span class='author'>作者：新作者</span></main>"
        let unchanged = try await BookInfo.analyze(source: source, book: book, body: html, baseURL: "https://example.invalid/book/1")
        XCTAssertEqual(unchanged.name, "原名")
        XCTAssertEqual(unchanged.author, "原作者")
        XCTAssertEqual(unchanged.tocUrl, "https://example.invalid/book/1")
        let changed = try await BookInfo.analyze(source: source, book: book, body: html, baseURL: "https://example.invalid/book/1", canReName: true)
        XCTAssertEqual(changed.name, "新名")
        XCTAssertEqual(changed.author, "新作者")
    }

    private func html(_ client: ReplayHttpClient, path: String, body: String, finalPath: String? = nil, status: Int = 200) async {
        let url = URL(string: "https://example.invalid" + path)!
        await client.enqueue(url: url, response: HttpResponse(status: status, body: Data(body.utf8),
            finalURL: URL(string: "https://example.invalid" + (finalPath ?? path))!))
    }

    private func bookAndChapter() -> (Book, BookChapter) {
        var book = Book(now: 0); book.name = "航海记"; book.origin = "https://example.invalid"
        book.bookUrl = "https://example.invalid/book/1"; book.tocUrl = "https://example.invalid/toc/1"
        var chapter = BookChapter(); chapter.title = "启航"; chapter.url = "/read/1"
        chapter.baseUrl = "https://example.invalid/toc/1"; chapter.bookUrl = book.bookUrl
        return (book, chapter)
    }

    func testRepeatedContentContinuesUntilURLCycle() async throws {
        let client = ReplayHttpClient()
        await html(client, path: "/read/1", body: "<div class='content'>重复页</div><a class='next' href='/read/1-2'>下一页</a>")
        await html(client, path: "/read/1-2", body: "<div class='content'>重复页</div><a class='next' href='/read/1-3'>下一页</a>")
        await html(client, path: "/read/1-3", body: "<div class='content'>末页</div><a class='next' href='/read/1'>首页</a>")
        let (book, chapter) = bookAndChapter()
        let result = try await WebBook(source: source(), client: client).content(book: book, chapter: chapter)
        XCTAssertEqual(result.text, "启航\n　　重复页\n　　重复页\n　　末页")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 3)
    }

    func testNextChapterBoundaryAndRedirectBase() async throws {
        let client = ReplayHttpClient()
        await html(client, path: "/read/1", body: "<div class='content'><img src='photo.jpg'><p>正文</p></div><a class='next' href='2'>下章</a>", finalPath: "/redirect/1")
        let (book, chapter) = bookAndChapter()
        let result = try await WebBook(source: source(), client: client).content(book: book, chapter: chapter, nextChapterUrl: "2")
        XCTAssertTrue(result.rawContent.contains("https://example.invalid/redirect/photo.jpg"))
        XCTAssertEqual(result.imageStyle, "FULL")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testMultipleTocLinksDoNotRecurseAndKeepLastDuplicate() async throws {
        let client = ReplayHttpClient()
        await html(client, path: "/toc/1", body: "<div class='chapter'><a href='/a'>甲</a></div><a class='next' href='/toc/2'>2</a><a class='next' href='/toc/3'>3</a>")
        await html(client, path: "/toc/2", body: "<div class='chapter'><a href='/b'>乙</a></div><a class='next' href='/unrequested'>更多</a>")
        await html(client, path: "/toc/3", body: "<div class='chapter'><a href='/a'>甲新版</a></div>")
        var (book, _) = bookAndChapter()
        let chapters = try await WebBook(source: source(), client: client, now: { 100 }).chapterList(book: &book)
        XCTAssertEqual(chapters.map(\.title), ["乙", "甲新版"])
        XCTAssertEqual(book.lastCheckTime, 100)
        XCTAssertEqual(book.lastCheckCount, 2)
        let requests = await client.requests
        XCTAssertEqual(requests.count, 3)
    }

    func testReverseTocAndVolumeFlags() async throws {
        for reverseRule in [false, true] {
            for reverseBook in [false, true] {
                let client = ReplayHttpClient()
                var source = try source()
                source.ruleToc?.chapterList = reverseRule ? "-class.chapter" : "class.chapter"
                source.ruleToc?.isVolume = "tag.a@data-volume"
                await html(client, path: "/toc/1", body: "<div class='chapter'><a data-volume='true'>卷一</a></div><div class='chapter'><a href='/a' data-vip='False' data-pay='0.0'>甲</a></div>")
                var (book, _) = bookAndChapter(); book.readConfig = ReadConfig(); book.readConfig?.reverseToc = reverseBook
                let chapters = try await WebBook(source: source, client: client).chapterList(book: &book)
                XCTAssertEqual(chapters.map(\.title), reverseRule != reverseBook ? ["甲", "卷一"] : ["卷一", "甲"])
                let volume = try XCTUnwrap(chapters.first(where: \.isVolume))
                XCTAssertEqual(volume.url, "卷一0")
                XCTAssertFalse(chapters.first(where: { !$0.isVolume })!.isVip)
                XCTAssertFalse(chapters.first(where: { !$0.isVolume })!.isPay)
            }
        }
    }

    func testEmptyTocAndContentFail() async throws {
        let client = ReplayHttpClient()
        await html(client, path: "/toc/1", body: "<html></html>")
        await html(client, path: "/read/1", body: "<html></html>")
        var (book, chapter) = bookAndChapter()
        let web = WebBook(source: try source(), client: client)
        do { _ = try await web.chapterList(book: &book); XCTFail("空目录应报错") }
        catch { XCTAssertEqual(error as? WebBookError, .emptyToc) }
        do { _ = try await web.content(book: book, chapter: chapter); XCTFail("空正文应报错") }
        catch { XCTAssertEqual(error as? WebBookError, .emptyContent) }
    }

    func testHTTPStatusFailure() async throws {
        let client = ReplayHttpClient()
        await html(client, path: "/search?key=demo&page=1", body: "failure", status: 503)
        do { _ = try await WebBook(source: source(), client: client).search(key: "demo"); XCTFail("HTTP 错误应报错") }
        catch { XCTAssertEqual(error as? WebBookError, .httpStatus(503, "https://example.invalid/search?key=demo&page=1")) }
    }

    func testReplacementTitleExcludeDisabledAndParagraphDedup() throws {
        var rule = ReplaceRule(now: 1); rule.pattern = "旧"; rule.replacement = "新"; rule.isRegex = false
        rule.scopeTitle = true; rule.scopeContent = false
        var excluded = rule; excluded.id = 2; excluded.replacement = "排除"; excluded.excludeScope = "航海记"
        var disabled = rule; disabled.id = 3; disabled.replacement = "禁用"; disabled.isEnabled = false
        let processor = ContentProcessor(rules: [rule, excluded, disabled])
        let (book, initial) = bookAndChapter(); var chapter = initial; chapter.title = "旧标题"
        let result = try processor.getContent(book: book, chapter: chapter, content: "旧标题\n旧段落\n旧段落", removeDuplicateParagraphs: true)
        XCTAssertEqual(result.text, "新标题\n　　旧段落")
        XCTAssertTrue(result.sameTitleRemoved)
    }

    func testRegexTimeoutUsesInjectedMonotonicClockAndDefaultTimeout() throws {
        var rule = ReplaceRule(now: 1); rule.pattern = "a"; rule.replacement = "b"; rule.timeoutMillisecond = 1
        var tick = 0.0
        let processor = ContentProcessor(clock: { tick += 0.01; return tick })
        XCTAssertThrowsError(try processor.apply(rule, to: "aaaa")) { XCTAssertEqual($0 as? ContentProcessorError, .regexTimeout(1)) }
        rule.timeoutMillisecond = 0
        XCTAssertEqual(try processor.apply(rule, to: "aaaa"), "bbbb")
        rule.pattern = "a|"
        XCTAssertThrowsError(try processor.apply(rule, to: "aaaa")) { XCTAssertEqual($0 as? ContentProcessorError, .invalidRule(1)) }
    }

    func testCancelledTaskMakesNoRequests() async throws {
        let client = ReplayHttpClient()
        let source = try source()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await WebBook(source: source, client: client).search(key: "demo")
        }
        do { _ = try await task.value; XCTFail("取消应传播") }
        catch { XCTAssertTrue(error is CancellationError) }
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testJavaReplacementTemplateAndInvalidGroup() throws {
        var rule = ReplaceRule(now: 1); rule.pattern = "(?<word>海)(风)?"; rule.replacement = "${word}-$12-\\$"
        let processor = ContentProcessor()
        XCTAssertEqual(try processor.apply(rule, to: "海风"), "海-海2-$")
        rule.replacement = "$9"
        XCTAssertThrowsError(try processor.apply(rule, to: "海风"))
    }

    func testFormatJsRetainsGlobalCounterAcrossChapters() async throws {
        let client = ReplayHttpClient()
        await html(client, path: "/toc/1", body: "<div class='chapter'><a href='/a'>甲</a></div><div class='chapter'><a href='/b'>乙</a></div>")
        var source = try source(); source.ruleToc?.formatJs = "gInt++; title + gInt"
        var (book, _) = bookAndChapter()
        let chapters = try await WebBook(source: source, client: client).chapterList(book: &book)
        XCTAssertEqual(chapters.map(\.title), ["甲1", "乙2"])
    }

    func testMultipleContentLinksAndPayMetadata() async throws {
        let client = ReplayHttpClient()
        await html(client, path: "/read/1", body: "<div class='content'>第一页</div><a class='next' href='/read/1-2'>2</a><a class='next' href='/read/1-3'>3</a>")
        await html(client, path: "/read/1-2", body: "<div class='content'>第二页</div><a class='next' href='/unrequested'>更多</a>")
        await html(client, path: "/read/1-3", body: "<div class='content'>第三页</div>")
        var source = try source(); source.ruleContent?.payAction = "'https://example.invalid/pay'"
        let (book, chapter) = bookAndChapter()
        let result = try await WebBook(source: source, client: client).content(book: book, chapter: chapter)
        XCTAssertEqual(result.text, "启航\n　　第一页\n　　第二页\n　　第三页")
        XCTAssertEqual(result.payAction, source.ruleContent?.payAction)
        let requests = await client.requests
        XCTAssertEqual(requests.count, 3)
    }

    func testPayActionIsExplicitAndReceivesChapterBindings() async throws {
        var source = try source()
        source.ruleContent?.payAction = "book.bookUrl + '?chapter=' + chapter.index"
        let client = ReplayHttpClient()
        var (book, chapter) = bookAndChapter(); chapter.index = 3
        let action = try await WebBook(source: source, client: client).resolvePayAction(book: book, chapter: chapter)
        XCTAssertEqual(action, "https://example.invalid/book/1?chapter=3")
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testSourceTypeWordCountAndSearchReversal() async throws {
        var source = try source(); source.bookSourceType = 2
        source.ruleSearch?.bookList = "-class.book"
        source.ruleSearch?.wordCount = "class.words@text"
        let html = "<div class='book'><a class='name' href='/1'>甲</a><span class='words'>12345</span></div><div class='book'><a class='name' href='/2'>乙</a><span class='words'>100</span></div>"
        let results = try await BookList.analyze(source: source, body: html, baseURL: "https://example.invalid/search")
        XCTAssertEqual(results.map(\.name), ["乙", "甲"])
        XCTAssertEqual(results.map(\.wordCount), ["100字", "1.2万字"])
        XCTAssertEqual(results.map(\.type), [64, 64])
    }

    func testContentScriptContextAndTitleImage() async throws {
        let client = ReplayHttpClient()
        await html(client, path: "/read/1", body: "<html></html>")
        var source = try source()
        source.ruleContent?.content = "@js: book.name + chapter.index + nextChapterUrl"
        source.ruleContent?.title = "@js: '图章https://example.invalid/title.png'"
        let (book, chapter) = bookAndChapter()
        let result = try await WebBook(source: source, client: client).content(book: book, chapter: chapter, nextChapterUrl: "/read/2")
        XCTAssertEqual(result.chapter.title, "图章")
        XCTAssertEqual(result.chapter.imgUrl, "https://example.invalid/title.png")
        XCTAssertTrue(result.text.contains("航海记0/read/2"))
    }
}
