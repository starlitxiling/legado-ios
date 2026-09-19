import XCTest
@testable import LegadoCore

final class WebBookContentFlowTests: XCTestCase {
    private func source() -> BookSource {
        var source = BookSource()
        source.bookSourceUrl = "https://content.test"
        source.ruleContent = ContentRule()
        source.ruleContent?.content = "tag.p@text"
        return source
    }

    private func book(type: Int = 8) -> Book {
        var book = Book(now: 0)
        book.bookUrl = "https://content.test/book"
        book.tocUrl = "https://content.test/toc"
        book.type = type
        return book
    }

    private func chapter() -> BookChapter {
        var chapter = BookChapter()
        chapter.url = "https://content.test/chapter"
        chapter.title = "Chapter"
        return chapter
    }

    private func enqueue(_ client: ReplayHttpClient, path: String = "/chapter", body: String) async {
        let url = URL(string: "https://content.test" + path)!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data(body.utf8), finalURL: url))
    }

    func testContentAndImagesAreCachedAcrossWebBookInstances() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var source = source()
        source.ruleContent?.content = "@js:result"
        let client = ReplayHttpClient()
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='8' height='8'><rect width='8' height='8'/></svg>"
        await enqueue(client, body: "<p>Body</p><img src='/image.svg'>")
        await enqueue(client, path: "/image.svg", body: svg)
        let configuration = WebBookConfiguration(cacheDirectory: directory)
        let first = try await WebBook(source: source, client: client, configuration: configuration)
            .content(book: book(), chapter: chapter(), includeTitle: false)
        let second = try await WebBook(source: source, client: client, configuration: configuration)
            .content(book: book(), chapter: chapter(), includeTitle: true)
        XCTAssertEqual(first.rawContent, second.rawContent)
        XCTAssertNotEqual(first.text, second.text)
        XCTAssertTrue(BookHelp.hasImageContent(directory: directory, book: book(), chapter: chapter()))
        XCTAssertEqual(try BookHelp.imageData(directory: directory, book: book(), src: "https://content.test/image.svg"), Data(svg.utf8))
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testFailedImageDownloadRetriesOnlyMissingImage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var source = source()
        source.ruleContent?.content = "@js:result"
        let client = ReplayHttpClient()
        await enqueue(client, body: "<p>Body</p><img src='/image.svg'>")
        await client.enqueue(url: URL(string: "https://content.test/image.svg")!, error: URLError(.timedOut))
        await enqueue(client, path: "/image.svg", body: "<svg xmlns='http://www.w3.org/2000/svg' width='8' height='8'/>")
        let web = WebBook(source: source, client: client, configuration: .init(cacheDirectory: directory))
        do { _ = try await web.content(book: book(), chapter: chapter()); XCTFail("Expected image failure") }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        _ = try await web.content(book: book(), chapter: chapter())
        let requests = await client.requests
        XCTAssertEqual(requests.map { $0.url.path }, ["/chapter", "/image.svg", "/image.svg"])
    }

    func testPureJSContentUsesSameCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var source = source()
        source.mainJs = "function getContent(){return 'Cached JS'}"
        let configuration = WebBookConfiguration(cacheDirectory: directory)
        _ = try await WebBook(source: source, client: ReplayHttpClient(), configuration: configuration)
            .content(book: book(), chapter: chapter())
        source.mainJs = "function getContent(){throw 'must use cache'}"
        let result = try await WebBook(source: source, client: ReplayHttpClient(), configuration: configuration)
            .content(book: book(), chapter: chapter())
        XCTAssertEqual(result.rawContent, "Cached JS")
    }

    func testTextSourceCanUseWebViewRules() async throws {
        actor Browser: HeadlessWebViewProtocol {
            var requests: [HeadlessWebViewRequest] = []
            func load(_ request: HeadlessWebViewRequest) -> StrResponse {
                requests.append(request)
                return StrResponse(raw: HttpResponse(status: 200, finalURL: URL(string: request.url!)!),
                    body: "<p>Rendered</p>")
            }
        }
        let browser = Browser()
        var source = source()
        source.ruleContent?.webJs = "document.body.innerHTML"
        source.ruleContent?.sourceRegex = "content"
        var chapter = chapter()
        chapter.url = (chapter.url ?? "") + #",{"webView":true}"#
        let result = try await WebBook(source: source, client: ReplayHttpClient(),
            configuration: .init(headlessWebView: browser)).content(book: book(), chapter: chapter)
        XCTAssertEqual(result.rawContent, "Rendered")
        let requests = await browser.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.javaScript, source.ruleContent?.webJs)
        XCTAssertEqual(requests.first?.sourceRegex, source.ruleContent?.sourceRegex)
    }

    func testWebJSWithoutWebViewOptionKeepsOrdinaryHTTPRequest() async throws {
        var source = source()
        source.ruleContent?.webJs = "throw 'unused browser script'"
        source.ruleContent?.sourceRegex = "content"
        let client = ReplayHttpClient()
        await enqueue(client, body: "<p>Ordinary</p>")
        let result = try await WebBook(source: source, client: client).content(book: book(), chapter: chapter())
        XCTAssertEqual(result.rawContent, "Ordinary")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testSubContentAppendsTextAndStoresMediaVariables() async throws {
        for type in [8, 32, 4, 64] {
            var source = source()
            source.ruleContent?.subContent = "tag.aside@text"
            let client = ReplayHttpClient()
            await enqueue(client, body: "<p>Main</p><aside>Extra</aside>")
            let result = try await WebBook(source: source, client: client).content(book: book(type: type), chapter: chapter())
            XCTAssertEqual(result.rawContent, type == 8 ? "Main\nExtra" : "Main")
            let binding = try JsChapterBinding(result.chapter)
            XCTAssertEqual(binding.value(for: "lyric"), type == 32 ? "Extra" : nil)
            XCTAssertEqual(binding.value(for: "danmaku"), type == 4 ? "Extra" : nil)
        }
    }

    func testMediaSubContentLoadsURLAndPropagatesCancellation() async throws {
        for cancel in [false, true] {
            var source = source()
            source.ruleContent?.subContent = "tag.aside@text"
            let client = ReplayHttpClient()
            await enqueue(client, body: "<p>Media</p><aside>https://content.test/lyrics</aside>")
            if cancel { await client.enqueue(url: URL(string: "https://content.test/lyrics")!, error: CancellationError()) }
            else { await enqueue(client, path: "/lyrics", body: "[00:01]Words") }
            do {
                let result = try await WebBook(source: source, client: client).content(book: book(type: 32), chapter: chapter())
                XCTAssertFalse(cancel)
                XCTAssertEqual(try JsChapterBinding(result.chapter).value(for: "lyric"), "[00:01]Words")
            } catch { XCTAssertTrue(cancel && error is CancellationError) }
        }
    }

    func testSpecialHTMLSurvivesFormattingAndCanBeDisabled() async throws {
        let fragment = "<usehtml><table><tbody><tr><td>A &amp; B</td></tr></tbody></table></usehtml>"
        for enabled in [false, true] {
            var source = source()
            source.ruleContent?.content = "@js:result"
            let client = ReplayHttpClient()
            await enqueue(client, body: "<p>Before</p>" + fragment + "<p>After</p>")
            let result = try await WebBook(source: source, client: client,
                configuration: .init(adaptSpecialStyle: enabled)).content(book: book(), chapter: chapter())
            XCTAssertEqual(result.rawContent.contains(fragment), enabled)
            XCTAssertTrue(result.rawContent.contains("Before"))
            XCTAssertTrue(result.rawContent.contains("After"))
        }
    }

    func testOnlineTextReplacementRestoresFullWidthIndent() async throws {
        var source = source()
        source.ruleContent?.replaceRegex = "##Before##After"
        let client = ReplayHttpClient()
        await enqueue(client, body: "<p>Before</p><p>Next</p>")
        let result = try await WebBook(source: source, client: client).content(book: book(), chapter: chapter())
        XCTAssertEqual(result.rawContent, "\u{3000}\u{3000}After\n\u{3000}\u{3000}Next")
    }

    func testPureJSSourcePreservesPayActionAndImageStyle() async throws {
        var source = source()
        source.mainJs = "function getContent(){return 'Body'}"
        source.ruleContent?.payAction = "'https://content.test/pay'"
        source.ruleContent?.imageStyle = "TEXT"
        let web = WebBook(source: source, client: ReplayHttpClient())
        let result = try await web.content(book: book(), chapter: chapter())
        XCTAssertEqual(result.payAction, source.ruleContent?.payAction)
        XCTAssertEqual(result.imageStyle, "TEXT")
        let payURL = try await web.resolvePayAction(book: book(), chapter: chapter())
        XCTAssertEqual(payURL, "https://content.test/pay")
    }
}
