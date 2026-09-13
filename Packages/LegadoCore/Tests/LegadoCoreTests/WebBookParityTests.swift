import XCTest
import GRDB
@testable import LegadoCore

final class WebBookParityTests: XCTestCase {
    private func source() -> BookSource {
        var source = BookSource(); source.bookSourceUrl = "https://example.invalid"
        source.searchUrl = "/search"; source.ruleSearch = SearchRule()
        source.ruleSearch?.bookList = "class.book"; source.ruleSearch?.name = "tag.a@text"
        source.ruleSearch?.author = "class.author@text"; source.ruleSearch?.kind = "class.kind@text"
        source.ruleSearch?.bookUrl = "tag.a@href"
        source.ruleBookInfo = BookInfoRule(); source.ruleBookInfo?.name = "tag.h1@text"
        source.ruleToc = TocRule(); source.ruleToc?.chapterList = "tag.a"
        source.ruleToc?.chapterName = "text"; source.ruleToc?.chapterUrl = "href"
        source.ruleContent = ContentRule(); source.ruleContent?.content = "tag.p@text"
        source.ruleContent?.nextContentUrl = "tag.a@href"
        return source
    }
    private func book() -> Book {
        var book = Book(now: 0); book.name = "Book"; book.origin = "source"
        book.bookUrl = "https://example.invalid/original/book"; book.tocUrl = "https://example.invalid/toc"
        return book
    }
    private func chapter() -> BookChapter {
        var chapter = BookChapter(); chapter.title = "Title"; chapter.index = 2
        chapter.url = "https://example.invalid/read"; chapter.baseUrl = "https://example.invalid/toc"
        return chapter
    }
    private func enqueue(_ client: ReplayHttpClient, _ path: String, _ body: String, redirect: String? = nil) async {
        let url = URL(string: "https://example.invalid" + path)!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data(body.utf8),
            finalURL: URL(string: "https://example.invalid" + (redirect ?? path))!))
    }
    private func rule(_ id: Int64 = 1, pattern: String = "x", replacement: String = "y") -> ReplaceRule {
        var rule = ReplaceRule(now: id); rule.pattern = pattern; rule.replacement = replacement
        return rule
    }

    func test01IdenticalPagesAreRetainedUntilURLCycle() async throws {
        for links in ["<a href='/two'>next</a>", "<a href='/two'>2</a><a href='/three'>3</a>"] {
            let client = ReplayHttpClient()
            await enqueue(client, "/read", "<p>same</p>" + links)
            await enqueue(client, "/two", "<p>same</p><a href='/three'>next</a>")
            await enqueue(client, "/three", "<p>last</p><a href='/read'>cycle</a>")
            let result = try await WebBook(source: source(), client: client).content(book: book(), chapter: chapter())
            XCTAssertEqual(result.text, "Title\n　　same\n　　same\n　　last")
        }
    }
    func test02OriginalBaseAndRedirectAreDistinct() async throws {
        let client = ReplayHttpClient(); var source = source()
        source.ruleBookInfo?.intro = "@js:baseUrl"
        source.ruleBookInfo?.coverUrl = "tag.img@src"
        await enqueue(client, "/original/book", "<img src='cover.jpg'>", redirect: "/moved/book")
        let result = try await WebBook(source: source, client: client).bookInfo(book())
        XCTAssertEqual(result.tocUrl, "https://example.invalid/original/book")
        XCTAssertEqual(result.intro, "https://example.invalid/original/book")
        XCTAssertEqual(result.coverUrl, "https://example.invalid/moved/cover.jpg")
    }
    func test03URLUsesFirstSelectionBeforeFollowingScript() async throws {
        var source = source(); source.ruleSearch?.bookUrl = "tag.a@href@js:result + '?ok'"
        let results = try await BookList.analyze(source: source,
            body: "<div class='book'><a href='/one'>A</a><a href='/two'>B</a></div>", baseURL: "https://example.invalid/search")
        XCTAssertEqual(results.first?.bookUrl, "https://example.invalid/one?ok")
        source.ruleBookInfo?.tocUrl = "tag.a@href"
        let result = try await BookInfo.analyze(source: source, book: book(), body: "<a href='/one'>1</a><a href='/two'>2</a>", baseURL: "https://example.invalid/book")
        XCTAssertEqual(result.tocUrl, "https://example.invalid/one")
    }
    func test04FileSourceDownloadsAndEmptyError() async throws {
        var source = source(); source.bookSourceType = 3; source.ruleBookInfo?.downloadUrls = "tag.a@href"
        var book = book(); book.type = 136
        let result = try await BookInfo.analyzeDetails(source: source, book: book, body: "<a href='/a.epub'>A</a><a href='/b.epub'>B</a>", baseURL: "https://example.invalid/book")
        XCTAssertEqual(result.downloadURLs, ["https://example.invalid/a.epub", "https://example.invalid/b.epub"])
        do {
            _ = try await BookInfo.analyzeDetails(source: source, book: book, body: "", baseURL: "https://example.invalid/book")
            XCTFail("下载链接为空必须失败")
        } catch { XCTAssertEqual(error as? WebBookError, .emptyDownloadURLs) }
    }
    func test05OptionalErrorsPreserveBooksAndContent() async throws {
        var source = source(); let bad = "@js:throw new Error('optional')"
        source.ruleSearch?.kind = bad; source.ruleSearch?.coverUrl = bad
        source.ruleSearch?.wordCount = bad; source.ruleSearch?.intro = bad; source.ruleSearch?.lastChapter = bad
        let results = try await BookList.analyze(source: source, body: "<div class='book'><a href='/b'>B</a></div>", baseURL: "https://example.invalid/search")
        XCTAssertEqual(results.first?.bookUrl, "https://example.invalid/b")
        source.ruleBookInfo?.kind = bad; source.ruleBookInfo?.coverUrl = bad
        source.ruleBookInfo?.wordCount = bad; source.ruleBookInfo?.intro = bad; source.ruleBookInfo?.lastChapter = bad
        let info = try await BookInfo.analyze(source: source, book: book(), body: "", baseURL: "https://example.invalid/book")
        XCTAssertEqual(info.name, "Book")
        source.ruleContent?.title = bad
        let client = ReplayHttpClient(); await enqueue(client, "/read", "<p>body</p>")
        let content = try await WebBook(source: source, client: client).content(book: book(), chapter: chapter())
        XCTAssertEqual(content.chapter.title, "Title")
        XCTAssertThrowsError(try WebBookContext.optional { throw CancellationError() }) { XCTAssertTrue($0 is CancellationError) }
    }
    func test06ChapterBindingsIncludeMetadata() async throws {
        var source = source(); source.ruleToc?.updateTime = "data-tag"
        source.ruleToc?.isVip = "@js:chapter.title === 'A' && chapter.url === '/a' && chapter.tag === 'tag' && chapter.index === 0"
        source.ruleToc?.isPay = "@js:chapter.isVip"
        source.ruleToc?.formatJs = "chapter.index + ':' + chapter.tag + ':' + chapter.isVip + ':' + chapter.isPay"
        let client = ReplayHttpClient(); await enqueue(client, "/toc", "<a href='/a' data-tag='tag'>A</a>")
        var book = book(); let chapters = try await WebBook(source: source, client: client).chapterList(book: &book)
        XCTAssertEqual(chapters.first?.title, "0:tag:true:true")
    }
    func test07TocWordCountIsConfigurable() async throws {
        for enabled in [false, true] {
            var source = source(); source.ruleToc?.updateTime = "data-tag"
            let client = ReplayHttpClient(); await enqueue(client, "/toc", "<a href='/a' data-tag='昨日 字数：1.2万字 更新'>A</a>")
            var book = book()
            let chapters = try await WebBook(source: source, client: client, tocCountWords: enabled).chapterList(book: &book)
            XCTAssertEqual(chapters.first?.wordCount, enabled ? "1.2万字" : nil)
            XCTAssertEqual(chapters.first?.tag, enabled ? "昨日  更新" : "昨日 字数：1.2万字 更新")
        }
    }
    func test08BlankTitleReplacementAndNewlineOrder() throws {
        var empty = rule(pattern: "Title", replacement: "  "); empty.scopeTitle = true
        var follow = rule(2, pattern: "Title", replacement: "New\nTitle"); follow.scopeTitle = true
        var chapter = chapter(); chapter.title = "Ti\rtle\n"
        XCTAssertEqual(try ContentProcessor(rules: [empty, follow]).title(book: book(), chapter: chapter), "New\nTitle")
    }
    func test09ErrorsContinueAndTimeoutDisables() throws {
        var errors: [Int64] = [], disabled: [Int64] = []
        var bad = rule(pattern: "["); bad.scopeTitle = true
        var timeout = rule(2, pattern: "x"); timeout.timeoutMillisecond = 1
        var good = rule(3, pattern: "regexTimeout", replacement: "handled"); good.scopeTitle = true
        var ticks = 0.0
        let processor = ContentProcessor(rules: [bad, timeout, good], clock: { ticks += 0.01; return ticks },
            onError: { rule, _ in errors.append(rule.id) }, disableRule: { disabled.append($0) })
        let result = try processor.getContent(book: book(), chapter: chapter(), content: "x")
        XCTAssertEqual(disabled, [2])
        XCTAssertTrue(errors.contains(1))
        XCTAssertTrue(result.text.contains("handled"))
        XCTAssertEqual(try processor.title(book: book(), chapter: chapter()), "Title")
        XCTAssertEqual(disabled, [2])
        timeout.scopeTitle = true
        var following = rule(4, pattern: "Title", replacement: "After"); following.scopeTitle = true
        let titleProcessor = ContentProcessor(rules: [timeout, following], clock: { ticks += 0.01; return ticks },
            disableRule: { disabled.append($0) })
        XCTAssertEqual(try titleProcessor.title(book: book(), chapter: chapter()), "After")
        XCTAssertEqual(disabled, [2, 2])
    }
    func test10JavaScriptReplacementReceivesMatchAndEntities() throws {
        let rule = rule(pattern: "[ab]", replacement: "@js:result + chapter.index + book.name + '\\\\path'")
        XCTAssertEqual(try ContentProcessor().apply(rule, to: "a b", chapter: chapter(), book: book()), "a2Book\\path b2Book\\path")
    }
    func test11SQLiteLikeASCIIWildcardsAndBackslash() throws {
        let database = try DatabaseQueue()
        try database.write { try $0.execute(sql: "PRAGMA case_sensitive_like = OFF") }
        for (name, scope, expected) in [("book", "BOOK", true), ("B_k", "Book", false), ("B__k", "Book", true),
            ("B%k", "Book", true), ("b\\_k", "B\\ak", true), ("ä", "Ä", false)] {
            let baseline = try database.read { try Bool.fetchOne($0, sql: "SELECT ? LIKE '%' || ? || '%'", arguments: [scope, name])! }
            XCTAssertEqual(baseline, expected)
            var book = book(); book.name = name
            var rule = rule(); rule.scope = scope
            XCTAssertEqual(try ContentProcessor(rules: [rule]).getContent(book: book, chapter: chapter(), content: "x", includeTitle: false).text,
                           expected ? "　　y" : "　　x", "name=\(name), scope=\(scope)")
            rule.scope = nil; rule.excludeScope = scope
            XCTAssertEqual(try ContentProcessor(rules: [rule]).getContent(book: book, chapter: chapter(), content: "x", includeTitle: false).text,
                           expected ? "　　x" : "　　y")
        }
    }
    func test12ParagraphIndentIsInjected() throws {
        for indent in ["", "    ", "　　"] {
            XCTAssertEqual(try ContentProcessor(paragraphIndent: indent).getContent(book: book(), chapter: chapter(), content: "body").text,
                           "Title\n" + indent + "body")
        }
        var titleRule = rule(pattern: "Title", replacement: "Heading\nSubtitle"); titleRule.scopeTitle = true
        XCTAssertEqual(try ContentProcessor(rules: [titleRule], paragraphIndent: " ").getContent(book: book(), chapter: chapter(), content: "body").text,
                       "Heading\n Subtitle\n body")
    }
    func test13PrecisionSearchAndCheckKeyword() async throws {
        for precision in [false, true] {
            var source = source(); source.ruleSearch?.checkKeyWord = "校验词"
            let client = ReplayHttpClient()
            await enqueue(client, "/search", "<div class='book'><a href='/1'>A</a><span class='kind'>目标分类</span></div><div class='book'><a href='/2'>B</a></div>")
            let web = WebBook(source: source, client: client, precisionSearch: precision)
            let results = try await web.search(key: "目标")
            XCTAssertEqual(results.count, precision ? 1 : 2)
            XCTAssertEqual(web.checkKeyword(default: "默认"), "校验词")
        }
        for invalid in [" ", "httpabc", "a::b", "a++b", "a--b"] {
            var source = source(); source.ruleSearch?.checkKeyWord = invalid
            XCTAssertEqual(WebBook(source: source, client: ReplayHttpClient()).checkKeyword(default: "默认"), "默认")
        }
    }
}
