import XCTest
@testable import LegadoCore

final class MediaTests: XCTestCase {
    func testRejectedImageCacheCanBeRetriedWithFreshBytes() async throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/tmp/media-decode-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("image")
        try Data([0]).write(to: file)
        let client = ReplayHttpClient()
        let url = URL(string: "https://site.test/image")!
        for bytes in [Data([0]), Data([1])] {
            await client.enqueue(url: url, response: HttpResponse(status: 200, body: bytes, finalURL: url))
        }
        let downloader = ImageDownloader(client: client, cacheDirectory: directory)
        do {
            _ = try await downloader.load(url: url.absoluteString, cacheFile: file, validate: { $0 == Data([1]) })
            XCTFail("无效图片应被拒绝")
        } catch ImageDownloadError.invalidDecodeResult {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let data = try await downloader.load(url: url.absoluteString, cacheFile: file, validate: { $0 == Data([1]) })
        XCTAssertEqual(data, Data([1]))
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    @MainActor func testAudioUserPauseReleasesSessionButInterruptionRetainsRecovery() async {
        let engine = makeEngine(MediaTestPlayer())
        engine.load(chapterCount: 1)
        engine.play(); await engine.waitUntilSettled()
        var releases = 0
        engine.stateChanged = { if engine.shouldDeactivateAudioSession { releases += 1 } }
        engine.pause(reason: .interruption)
        XCTAssertEqual(engine.pauseReason, .interruption)
        XCTAssertEqual(releases, 0)
        engine.pause()
        XCTAssertEqual(engine.pauseReason, .user)
        XCTAssertEqual(releases, 1)
        engine.play(); await engine.waitUntilSettled()
        engine.pause()
        XCTAssertEqual(releases, 2)
    }

    func testMangaNormalizesLazyImagesAgainstEachRedirectedPage() async throws {
        let client = ReplayHttpClient()
        await client.enqueue(url: URL(string: "https://site.test/chapter")!, response: HttpResponse(status: 200,
            body: Data(#"<section><img src="placeholder" data-src="one.jpg"></section><a href="https://site.test/page2">next</a>"#.utf8),
            finalURL: URL(string: "https://cdn.test/first/chapter")!))
        await client.enqueue(url: URL(string: "https://site.test/page2")!, response: HttpResponse(status: 200,
            body: Data(#"<section><img data-original="two.jpg"></section>"#.utf8),
            finalURL: URL(string: "https://cdn.test/second/chapter")!))
        var source = BookSource(); source.bookSourceType = 2; source.bookSourceUrl = "https://site.test"
        var rule = ContentRule(); rule.content = "tag.section@html"; rule.nextContentUrl = "tag.a@href"; source.ruleContent = rule
        var book = Book(now: 0); book.type = 64
        var chapter = BookChapter(); chapter.url = "https://site.test/chapter"
        let result = try await WebBook(source: source, client: client).content(book: book, chapter: chapter)
        let images = try MediaContentResolver.images(result.rawContent, baseURL: chapter.url!)
        XCTAssertEqual(images.map(\.url.absoluteString), ["https://cdn.test/first/one.jpg", "https://cdn.test/second/two.jpg"])
        let lazy = try MediaContentResolver.images(#"<img data-srcset="three.jpg">"#, baseURL: "https://cdn.test/third/chapter")
        XCTAssertEqual(lazy.map(\.url.absoluteString), ["https://cdn.test/third/three.jpg"])
    }

    func testImageRequestRetainsMethodBodyJSAndOptions() async throws {
        let input = #"https://site.test/a,{"method":"POST","body":"payload","headers":{"Content-Type":"text/plain"},"js":"result + '?signed=1'","retry":1,"timeout":1200}"#
        let resource = try XCTUnwrap(MediaContentResolver.images(input, baseURL: "https://site.test").first)
        XCTAssertEqual(resource.imageRule, input)
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/tmp/media-request-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = MediaImageClient()
        _ = try await ImageDownloader(client: client, cacheDirectory: directory).load(url: resource.imageRule, isCover: false)
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.body, Data("payload".utf8))
        XCTAssertEqual(request.url.absoluteString, "https://site.test/a?signed=1")
    }

    func testTypesPreserveFlags() {
        var book = Book(now: 0)
        book.type = 32 | 256 | 16
        XCTAssertTrue(book.isAudio)
        XCTAssertFalse(book.isImage)
        book.type = 64 | 1024
        XCTAssertTrue(book.isImage)
        XCTAssertEqual(BookMediaKind(type: 136), .file)
        XCTAssertEqual(BookMediaKind(type: 4), .video)
        XCTAssertEqual(BookMediaKind(type: 8), .text)
        var source = BookSource()
        for (value, expected) in [(0, 8), (1, 32), (2, 64), (3, 136), (4, 4)] {
            source.bookSourceType = value
            XCTAssertEqual(source.mediaBookType, expected)
        }
    }

    func testImagesPreserveOrderDuplicatesAndHeaders() throws {
        let content = #"<img src='/a.jpg?x=1&amp;y=2'>"# + "\n" +
            #"https://images.test/b.jpg,{{"Referer":"https://site.test/"}}"# + "\n" +
            "https://images.test/b.jpg\nhttps://images.test/b.jpg"
        let images = try MediaContentResolver.images(content, baseURL: "https://site.test/chapter")
        XCTAssertEqual(images.count, 4)
        XCTAssertEqual(images[0].url.absoluteString, "https://site.test/a.jpg?x=1&y=2")
        XCTAssertEqual(images[1].headers["Referer"], "https://site.test/")
        XCTAssertEqual(images[2], images[3])
    }

    func testImagesRejectInvalidHeadersAndIgnoreText() throws {
        XCTAssertTrue(try MediaContentResolver.images("正文文字\n", baseURL: "https://site.test").isEmpty)
        XCTAssertThrowsError(try MediaContentResolver.images("https://site.test/a,{{bad}}", baseURL: "https://site.test"))
    }

    func testImageTagContainsUnescapedJSONHeaders() throws {
        let images = try MediaContentResolver.images(
            #"<img src="/a.jpg,{"headers":{"Referer":"https://site.test/"}}" alt="page">"#,
            baseURL: "https://site.test/chapter")
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].headers["Referer"], "https://site.test/")
        XCTAssertEqual(images[0].url.absoluteString, "https://site.test/a.jpg")
        let escaped = try MediaContentResolver.images(
            #"<img src="/a.jpg,{&quot;headers&quot;:{&quot;Referer&quot;:&quot;https://site.test/&quot;}}">"#,
            baseURL: "https://site.test/chapter")
        XCTAssertEqual(escaped, images)
    }

    func testAudioURLRulesMergeSourceAndRequestHeaders() async throws {
        var source = BookSource()
        source.bookSourceType = 1
        source.header = #"{"Referer":"https://site.test/","X-Token":"old"}"#
        var book = Book(now: 0); book.type = 32
        var chapter = BookChapter(); chapter.url = "https://site.test/chapter"; chapter.title = "sound"
        let resource = try await MediaContentResolver.audioAddress(
            #"@js: 'https://site.test/' + chapter.title + '.mp3,{"headers":{"X-Token":"new"}}'"#,
            source: source, book: book, chapter: chapter, client: MediaFixtureClient())
        XCTAssertEqual(resource.url.absoluteString, "https://site.test/sound.mp3")
        XCTAssertEqual(resource.headers["Referer"], "https://site.test/")
        XCTAssertEqual(resource.headers["X-Token"], "new")
    }

    func testAudioContentWebViewRuleIsForwarded() async throws {
        var source = BookSource(); source.bookSourceType = 1
        source.bookSourceUrl = "https://site.test"
        var rule = ContentRule(); rule.content = "@js: result"; rule.webJs = "result"; rule.sourceRegex = "\\.mp3"
        source.ruleContent = rule
        var book = Book(now: 0); book.type = 32
        var chapter = BookChapter(); chapter.url = "https://site.test/chapter"
        let resource = try await MediaContentResolver.audio(source: source, book: book, chapter: chapter, client: MediaFixtureClient())
        XCTAssertEqual(resource.url.absoluteString, "https://site.test/sound.mp3")
    }

    func testImageHeadersDecodeAndDiskCache() async throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/media-image-tests/" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = MediaImageClient()
        var source = BookSource(); source.bookSourceUrl = "https://site.test"; source.bookSourceType = 2
        source.header = #"{"Referer":"https://site.test/"}"#
        var rule = ContentRule(); rule.imageDecode = "result.map(function(x) { return x + 1; })"; source.ruleContent = rule
        let downloader = ImageDownloader(client: client, cacheDirectory: directory)
        let resource = try XCTUnwrap(MediaContentResolver.images(#"https://site.test/a,{{"X-Image":"yes"}}"#,
            baseURL: "https://site.test").first)
        let first = try await downloader.load(url: resource.imageRule, source: source, isCover: false)
        let second = try await downloader.load(url: resource.imageRule, source: source, isCover: false)
        XCTAssertEqual(first, Data([2, 3])); XCTAssertEqual(second, first)
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.headers["X-Image"], "yes")
        XCTAssertEqual(requests.first?.headers["Referer"], "https://site.test/")
    }

    func testAudioCookiesAreScopedToMediaHost() async throws {
        let cookies = CookieStore()
        await cookies.setCookie(url: "https://site.test", cookie: "site=secret")
        await cookies.setCookie(url: "https://cdn.test", cookie: "cdn=media")
        var source = BookSource(); source.bookSourceUrl = "https://site.test"
        var chapter = BookChapter(); chapter.url = "https://site.test/chapter"
        let resource = try await MediaContentResolver.audioAddress("https://cdn.test/a.mp3", source: source,
            book: Book(now: 0), chapter: chapter, client: MediaFixtureClient(), cookies: cookies)
        XCTAssertEqual(resource.headers["Cookie"], "cdn=media")
    }

    func testAudioCarriesCookiesSetWhileResolvingContent() async throws {
        var source = BookSource(); source.bookSourceUrl = "https://site.test"; source.bookSourceType = 1
        var rule = ContentRule(); rule.content = "@js: result"; source.ruleContent = rule
        var book = Book(now: 0); book.type = 32
        var chapter = BookChapter(); chapter.url = "https://site.test/chapter"
        let resource = try await MediaContentResolver.audio(source: source, book: book, chapter: chapter, client: MediaCookieClient())
        XCTAssertEqual(resource.headers["Cookie"], "media=session")
    }

    @MainActor func testAudioPlayPauseSeekAndSwitch() async {
        let player = MediaTestPlayer()
        let engine = makeEngine(player)
        engine.load(chapterCount: 3, chapter: 1, position: 1200)
        engine.play(); await engine.waitUntilSettled()
        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(player.position, 1200)
        engine.pause(); XCTAssertEqual(engine.state, .paused)
        engine.play(); await engine.waitUntilSettled()
        engine.seek(to: 4500); XCTAssertEqual(engine.position, 4500)
        engine.next(); await engine.waitUntilSettled()
        XCTAssertEqual(engine.chapter, 2); XCTAssertEqual(engine.position, 0)
        engine.previous(); await engine.waitUntilSettled()
        XCTAssertEqual(engine.chapter, 1)
        engine.stop(); XCTAssertEqual(engine.state, .stopped)
    }

    @MainActor func testAudioEndAndBoundedRetry() async {
        let player = MediaTestPlayer()
        let engine = makeEngine(player)
        engine.load(chapterCount: 2)
        engine.play(); await engine.waitUntilSettled()
        player.onEvent?(.ended)
        await engine.waitUntilSettled()
        XCTAssertEqual(engine.chapter, 1)
        player.onEvent?(.progress(position: 7000, duration: 9000))
        player.onEvent?(.failed("failure")); await engine.waitUntilSettled()
        XCTAssertEqual(engine.position, 7000)
        XCTAssertEqual(engine.retryCount, 1)
        player.onEvent?(.failed("failure")); await engine.waitUntilSettled()
        player.onEvent?(.failed("failure")); await engine.waitUntilSettled()
        XCTAssertEqual(engine.state, .failed)
        XCTAssertEqual(engine.errorMessage, "failure")
        engine.play(); await engine.waitUntilSettled()
        player.onEvent?(.ended)
        XCTAssertEqual(engine.state, .stopped)
    }

    @MainActor func testTimerAndLoadingTimeoutUseInjectedClock() async {
        var time: TimeInterval = 0
        let player = MediaTestPlayer()
        let engine = makeEngine(player, now: { time })
        engine.load(chapterCount: 1)
        engine.play(); await engine.waitUntilSettled()
        engine.setTimer(seconds: 10)
        time = 9; engine.tick(); XCTAssertEqual(engine.state, .playing)
        time = 10; engine.tick(); XCTAssertEqual(engine.state, .stopped)
        engine.play(); await engine.waitUntilSettled()
        player.onEvent?(.buffering)
        time = 80; engine.tick(); await engine.waitUntilSettled()
        XCTAssertEqual(engine.retryCount, 1)
    }

    @MainActor func testStalePlayerEventsCannotAdvanceNewChapter() async {
        let player = MediaTestPlayer()
        let engine = makeEngine(player)
        engine.load(chapterCount: 3)
        engine.play(); await engine.waitUntilSettled()
        let old = player.onEvent
        engine.next(); await engine.waitUntilSettled()
        old?(.ended)
        old?(.progress(position: 900, duration: 1000))
        XCTAssertEqual(engine.chapter, 1)
        XCTAssertEqual(engine.position, 0)
    }

    @MainActor private func makeEngine(_ player: MediaTestPlayer,
                                      now: @escaping () -> TimeInterval = { 0 }) -> AudioPlayEngine {
        AudioPlayEngine(player: player, now: now) { _ in
            MediaResource(url: URL(string: "https://site.test/audio.mp3")!)
        }
    }
}

private struct MediaFixtureClient: SourceScriptClient {
    func configureSourceBindings(_ engine: JsEngine) { engine.headlessWebView = MediaWebView() }
    func checkResponse(_ response: StrResponse) async throws -> StrResponse { response }
    func loginHeaders(url: String, headers: [String: String]) throws -> [String: String] { headers }
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        HttpResponse(status: 200, body: Data("https://site.test/sound.mp3".utf8), finalURL: request.url)
    }
}

private struct MediaWebView: HeadlessWebViewProtocol {
    func load(_ request: HeadlessWebViewRequest) async throws -> StrResponse {
        XCTAssertEqual(request.sourceRegex, "\\.mp3")
        return StrResponse(raw: HttpResponse(status: 200, finalURL: URL(string: request.url ?? "https://site.test")!), body: "https://site.test/sound.mp3")
    }
}

private actor MediaImageClient: HttpClient {
    private(set) var requests: [HttpRequest] = []
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        requests.append(request)
        return HttpResponse(status: 200, body: Data([1, 2]), finalURL: request.url)
    }
}

private struct MediaCookieClient: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        HttpResponse(status: 200, body: Data("https://site.test/a.mp3".utf8), finalURL: request.url,
                     headers: ["Set-Cookie": "media=session; Path=/"])
    }
}

@MainActor private final class MediaTestPlayer: AudioPlayer {
    var onEvent: ((AudioPlayerEvent) -> Void)?
    var position = 0
    func prepare(_ resource: MediaResource, position: Int) async throws { self.position = position }
    func play() throws {}
    func pause() {}
    func stop() {}
    func seek(to position: Int) { self.position = position }
}
