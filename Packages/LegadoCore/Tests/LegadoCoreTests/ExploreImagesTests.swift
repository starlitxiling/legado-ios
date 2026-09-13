import XCTest
@testable import LegadoCore

final class ExploreImagesTests: XCTestCase {
    func testPersistentInfoMapAndSourceVariableSurviveCacheClear() async throws {
        let database = try AppDatabase.inMemory()
        let state = SourceStateRepository(database: database)
        var source = BookSource(); source.bookSourceUrl = "https://example.org"
        source.exploreUrl = """
        <js>
        var count = Number(infoMap.get('count') || 0) + 1;
        infoMap.put('count', String(count)); infoMap.save();
        source.setVariable(String(Number(source.getVariable() || 0) + 1));
        JSON.stringify([{title:String(count),url:'/list'}]);
        </js>
        """
        let first = try await ExploreKinds.load(source: source, client: ReplayHttpClient(), stateRepository: state)
        XCTAssertEqual(first.first?.title, "1")
        let cached = try await ExploreKinds.load(source: source, client: ReplayHttpClient(), stateRepository: state)
        XCTAssertEqual(cached.first?.title, "1")
        try await ExploreKinds.clearCache(source: source, stateRepository: state)
        let second = try await ExploreKinds.load(source: source, client: ReplayHttpClient(), stateRepository: state)
        XCTAssertEqual(second.first?.title, "2")
        let stored = try await state.load(source: source.bookSourceUrl!)
        XCTAssertEqual(stored["variable"], "2")
    }

    func testImageCacheSurvivesReadingProgressChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient(), url = URL(string: "https://example.org/a.png?size=1")!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data([1]), finalURL: url))
        let downloader = ImageDownloader(client: client, cacheDirectory: directory)
        var book = Book(now: 0); book.name = "测试书"; book.author = "作者"; book.bookUrl = "https://example.org/book"
        _ = try await downloader.load(url: url.absoluteString, book: book, isCover: false)
        book.durChapterIndex = 8; book.durChapterPos = 200; book.durChapterTime = 900
        _ = try await downloader.load(url: url.absoluteString, book: book, isCover: false)
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)!
            .allObjects.compactMap { $0 as? URL }.filter { $0.pathExtension == "png" }
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.lastPathComponent, "0830a1143d5c3827.png")
        XCTAssertEqual(files.first?.deletingLastPathComponent().lastPathComponent, "测试书7285d2298dd750bc")
    }

    func testTextKindsAndGroupHeadings() throws {
        let kinds = try ExploreKinds.parse("分类\n热门::/hot?page={{page}}&&新书::/new")
        XCTAssertEqual(kinds.map(\.title), ["分类", "热门", "新书"])
        XCTAssertTrue(kinds[0].isHeading)
        XCTAssertEqual(kinds[1].url, "/hot?page={{page}}")
        XCTAssertTrue(try ExploreKinds.parse("  ").isEmpty)
    }

    func testJSONAndDynamicKinds() throws {
        let json = #"[{"title":"分组","type":"text"},{"title":"热门","url":"/hot"}]"#
        XCTAssertEqual(try ExploreKinds.parse(json).count, 2)
        XCTAssertThrowsError(try ExploreKinds.parse("[broken]"))
        var source = BookSource()
        source.exploreUrl = "<js>JSON.stringify([{title:'动态',url:'/list'}])</js>"
        XCTAssertEqual(try ExploreKinds.load(source: source, client: ReplayHttpClient()).first?.title, "动态")
        source.exploreUrl = "@js:'热门::/hot'"
        XCTAssertEqual(try ExploreKinds.load(source: source, client: ReplayHttpClient()).first?.url, "/hot")
    }

    func testExplorePagination() async throws {
        let client = ReplayHttpClient()
        var source = BookSource(); source.bookSourceUrl = "https://example.org"
        var rule = ExploreRule(); rule.bookList = "$.books[*]"; rule.name = "$.name"; rule.bookUrl = "$.url"
        source.ruleExplore = rule
        let web = WebBook(source: source, client: client)
        for page in 1...2 {
            let url = URL(string: "https://example.org/list?page=\(page)")!
            await client.enqueue(url: url, response: HttpResponse(status: 200,
                body: Data("{\"books\":[{\"name\":\"书\(page)\",\"url\":\"/book\(page)\"}]}".utf8), finalURL: url))
            let books = try await web.explore(url: "/list?page={{page}}", page: page)
            XCTAssertEqual(books.first?.name, "书\(page)")
        }
    }

    func testImageCacheHeadersCookiesAndDecode() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient(), cookies = CookieStore()
        let url = URL(string: "https://example.org/image")!
        await cookies.setCookie(url: url.absoluteString, cookie: "session=ok")
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data([1, 2, 3]), finalURL: url))
        var source = BookSource(); source.bookSourceUrl = "https://example.org"
        source.header = #"{"Referer":"https://example.org/book"}"#
        source.coverDecodeJs = "result.map(function(x){return x + 1})"
        let downloader = ImageDownloader(client: client, cacheDirectory: directory, cookies: cookies)
        let first = try await downloader.load(url: url.absoluteString, source: source, isCover: true)
        let cached = try await downloader.load(url: url.absoluteString, source: source, isCover: true)
        XCTAssertEqual(first, Data([2, 3, 4])); XCTAssertEqual(cached, first)
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.headers["Referer"], "https://example.org/book")
        XCTAssertEqual(requests.first?.headers["Cookie"], "session=ok")
        var rule = ContentRule(); rule.imageDecode = "result.slice(1)"; source.ruleContent = rule
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data([1, 2, 3]), finalURL: url))
        let content = try await downloader.load(url: url.absoluteString, source: source, isCover: false)
        XCTAssertEqual(content, Data([2, 3]))
    }

    func testImageFailureIsNotCached() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient(), url = URL(string: "https://example.org/bad")!
        let downloader = ImageDownloader(client: client, cacheDirectory: directory)
        await client.enqueue(url: url, response: HttpResponse(status: 403, finalURL: url))
        do { _ = try await downloader.load(url: url.absoluteString); XCTFail("应拒绝 HTTP 错误") }
        catch { XCTAssertEqual(error as? WebBookError, .httpStatus(403, url.absoluteString)) }
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data([7]), finalURL: url))
        let data = try await downloader.load(url: url.absoluteString)
        XCTAssertEqual(data, Data([7]))
    }

    func testDecodeRejectsWrongTypeAndPreservesSignedBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloader = ImageDownloader(client: ReplayHttpClient(), cacheDirectory: directory)
        var source = BookSource(); source.coverDecodeJs = "result"
        let bytes = try await downloader.load(url: "data:image/png;base64,/wCA", source: source)
        XCTAssertEqual(bytes, Data([255, 0, 128]))
        source.coverDecodeJs = "'invalid'"
        do { _ = try await downloader.load(url: "data:image/png;base64,/wCA", source: source); XCTFail("应拒绝字符串") }
        catch { XCTAssertTrue(error is ImageDownloadError) }
    }
}
