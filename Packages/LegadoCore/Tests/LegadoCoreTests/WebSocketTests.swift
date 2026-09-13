import XCTest
@testable import LegadoCore

final class WebSocketTests: XCTestCase {
    func testHandshake() throws {
        XCTAssertEqual(WebSocketHandshake.accept(key: "dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
        let request = WebHttpRequest(method: "GET", target: "/bookSourceDebug", headers: [
            "Host": "reader.test", "Connection": "keep-alive, Upgrade", "Upgrade": "websocket", "Sec-WebSocket-Version": "13",
            "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==", "Sec-WebSocket-Protocol": "legado, legado.token.c2VjcmV0"])
        XCTAssertTrue(WebSocketHandshake.authorized(request, token: "secret", required: true))
        XCTAssertFalse(WebSocketHandshake.authorized(request, token: "wrong", required: true))
        let response = String(decoding: try WebSocketHandshake.response(request), as: UTF8.self)
        XCTAssertTrue(response.contains("101 Switching Protocols"))
        XCTAssertTrue(response.contains("Sec-WebSocket-Protocol: legado\r\n"))
        XCTAssertFalse(response.contains("token.c2VjcmV0"))
        XCTAssertThrowsError(try WebSocketHandshake.response(WebHttpRequest(method: "GET", target: "/searchBook")))
    }

    func testFrameLengthsAndMasks() throws {
        for size in [0, 125, 126, 65535, 65536] {
            for mask: [UInt8]? in [nil, [1, 2, 3, 4]] {
                let frame = WebSocketFrame(opcode: .binary, payload: Data(repeating: 42, count: size))
                let bytes = frame.encoded(mask: mask)
                var decoder = WebSocketFrameDecoder(requireMask: mask != nil)
                XCTAssertEqual(try decoder.append(Data(bytes.prefix(1))), [])
                XCTAssertEqual(try decoder.append(Data(bytes.dropFirst())), [frame])
            }
        }
    }

    func testFragmentsAndControlFrames() throws {
        var decoder = WebSocketFrameDecoder()
        let first = WebSocketFrame(opcode: .text, payload: Data([0xe4]), final: false)
        let ping = WebSocketFrame(opcode: .ping, payload: Data("ping".utf8))
        let last = WebSocketFrame(opcode: .continuation, payload: Data([0xbd, 0xa0]))
        let bytes = first.encoded(mask: [0, 1, 2, 3]) + ping.encoded(mask: [1, 2, 3, 4]) + last.encoded(mask: [4, 3, 2, 1])
        XCTAssertEqual(try decoder.append(bytes), [ping, .init(opcode: .text, payload: Data("你".utf8))])
    }

    func testRejectsInvalidFrames() throws {
        for bytes in [Data([0x81, 0]), Data([0x83, 0x80, 0, 0, 0, 0]),
                      WebSocketFrame(opcode: .continuation).encoded(mask: [0, 0, 0, 0]),
                      WebSocketFrame(opcode: .text, payload: Data([0xff])).encoded(mask: [0, 0, 0, 0]),
                      WebSocketFrame(opcode: .close, payload: Data([1])).encoded(mask: [0, 0, 0, 0]),
                      Data([0x82, 0xff, 0x80, 0, 0, 0, 0, 0, 0, 0])] {
            var decoder = WebSocketFrameDecoder()
            XCTAssertThrowsError(try decoder.append(bytes))
        }
    }

    func testCloseHandshake() throws {
        var state = WebSocketCloseState()
        let close = WebSocketFrame.close(code: 1000, reason: "调试结束")
        XCTAssertEqual(state.receive(close), close)
        XCTAssertTrue(state.received)
        XCTAssertTrue(state.sent)
        XCTAssertNil(state.receive(close))
        var local = WebSocketCloseState()
        XCTAssertEqual(local.initiate(code: 1000, reason: "Search finish"), .close(code: 1000, reason: "Search finish"))
        XCTAssertNil(local.receive(close))
        XCTAssertTrue(local.received)
    }

    func testRouteSequences() async throws {
        let routes = WebSocketRoutes(bookDebug: { tag, key in
            XCTAssertEqual(tag, "source"); XCTAssertEqual(key, "book")
            return AsyncStream { c in
                c.yield(.init(state: 10, message: "hidden"))
                c.yield(.init(state: 1, message: "start"))
                c.yield(.init(state: 1000, message: "done")); c.finish()
            }
        }, rssDebug: { tag in
            XCTAssertEqual(tag, "source")
            return AsyncStream { c in c.yield(.init(state: -1, message: "rss error")); c.finish() }
        }, search: { key in
            XCTAssertEqual(key, "book")
            return AsyncThrowingStream { c in c.yield([]); c.finish() }
        })
        func events(_ path: String, _ message: String) async -> [WebSocketRouteEvent] {
            var result: [WebSocketRouteEvent] = []
            for await event in routes.events(path: path, message: Data(message.utf8)) { result.append(event) }
            return result
        }
        let book = await events("/bookSourceDebug", #"{"tag":"source","key":"book"}"#)
        XCTAssertEqual(book, [.text("start"), .text("done"), .close(1000, "调试结束")])
        let rss = await events("/rssSourceDebug", #"{"tag":"source"}"#)
        XCTAssertEqual(rss, [.text("rss error"), .close(1000, "调试结束")])
        let search = await events("/searchBook", #"{"key":"book"}"#)
        XCTAssertEqual(search, [.text("[]"), .close(1000, "Search finish")])
        let malformed = await events("/searchBook", "[]")
        XCTAssertEqual(malformed, [.close(1008, "认证数据格式错误")])
    }

    func testRouterAuthorizationAndDebugPage() async throws {
        let api = WebApi(database: try .inMemory())
        let protected = HttpRouter(api: api, token: { "secret" })
        let request = WebHttpRequest(method: "GET", target: "/searchBook", headers: ["sec-websocket-protocol": "legado, legado.token.c2VjcmV0"])
        XCTAssertTrue(protected.authorizesWebSocket(request))
        XCTAssertFalse(protected.authorizesWebSocket(.init(method: "GET", target: "/searchBook", headers: ["x-legado-token": "secret"])))
        let open = HttpRouter(api: api, tokenRequired: { false })
        XCTAssertTrue(open.authorizesWebSocket(.init(method: "GET", target: "/searchBook", headers: ["sec-websocket-protocol": "legado"])))
        XCTAssertFalse(open.authorizesWebSocket(.init(method: "GET", target: "/searchBook")))
        let page = await protected.handle(.init(method: "GET", target: "/debug.html"))
        XCTAssertEqual(page.status, 200)
        XCTAssertTrue(String(decoding: page.body, as: UTF8.self).contains("JSON.stringify({tag,key})"))
    }

    func testLiveRoutesWithFakeHTTP() async throws {
        let database = try AppDatabase.inMemory()
        let api = WebApi(database: database)
        _ = await api.handle(.init(method: "POST", target: "/saveBookSource", body: Data(#"{"bookSourceUrl":"https://source.test","bookSourceName":"Test","searchUrl":"/search?key={{key}}","ruleSearch":{"bookList":"a","name":"text","bookUrl":"href"}}"#.utf8)))
        try await RssRepository(database: database).saveSources([RssSource(sourceUrl: "https://rss.test")])
        let routes = WebSocketRoutes.live(database: database, client: SocketFakeHTTP())
        var results: [String: [WebSocketRouteEvent]] = [:]
        for (path, message) in [
            ("/bookSourceDebug", #"{"tag":"https://source.test","key":"book"}"#),
            ("/rssSourceDebug", #"{"tag":"https://rss.test"}"#),
            ("/searchBook", #"{"key":"book"}"#),
            ("/bookSourceDebug", #"{"tag":"missing","key":"book"}"#)
        ] {
            var events: [WebSocketRouteEvent] = []
            for await event in routes.events(path: path, message: Data(message.utf8)) { events.append(event) }
            if message.contains("missing") { XCTAssertEqual(events, [.text("书源不存在"), .close(1000, "调试结束")]) }
            else { results[path] = events }
        }
        XCTAssertTrue(results["/bookSourceDebug"]?.contains(where: { if case .text(let text) = $0 { return text.contains("开始搜索关键字:book") }; return false }) == true)
        XCTAssertEqual(results["/bookSourceDebug"]?.last, .close(1000, "调试结束"))
        XCTAssertTrue(results["/rssSourceDebug"]?.contains(where: { if case .text(let text) = $0 { return text.contains("列表页解析成功，为空") }; return false }) == true)
        XCTAssertEqual(results["/rssSourceDebug"]?.last, .close(1000, "调试结束"))
        XCTAssertEqual(results["/searchBook"], [.text("[]"), .close(1000, "Search finish")])
    }

    func testFrameLimitsAndBinaryFragments() throws {
        var decoder = WebSocketFrameDecoder(maximumMessageSize: 3)
        XCTAssertEqual(try decoder.append(WebSocketFrame(opcode: .binary, payload: Data([0, 1]), final: false).encoded(mask: [0, 0, 0, 0])), [])
        XCTAssertThrowsError(try decoder.append(WebSocketFrame(opcode: .continuation, payload: Data([2, 3])).encoded(mask: [0, 0, 0, 0]))) { error in
            XCTAssertEqual(error as? WebSocketError, .tooLarge)
        }
        for bytes in [Data([0x82, 0xfe, 0, 125]), Data([0x09, 0x80]), Data([0xc1, 0x80]),
                      WebSocketFrame.close(code: 1005, reason: "").encoded(mask: [0, 0, 0, 0])] {
            var invalid = WebSocketFrameDecoder()
            XCTAssertThrowsError(try invalid.append(bytes))
        }
        var binary = WebSocketFrameDecoder()
        let frames = WebSocketFrame(opcode: .binary, payload: Data([255]), final: false).encoded(mask: [0, 0, 0, 0])
            + WebSocketFrame(opcode: .continuation, payload: Data([0])).encoded(mask: [0, 0, 0, 0])
        XCTAssertEqual(try binary.append(frames), [.init(opcode: .binary, payload: Data([255, 0]))])
    }

    func testSearchBookJSONFields() async throws {
        var book = SearchBook(now: 0)
        book.bookUrl = "https://book.test/1"; book.name = "小说"; book.author = "作者"; book.origin = "source"
        let routes = WebSocketRoutes(bookDebug: { _, _ in nil }, rssDebug: { _ in nil }, search: { _ in
            AsyncThrowingStream { $0.yield([book]); $0.finish() }
        })
        var output: [WebSocketRouteEvent] = []
        for await event in routes.events(path: "/searchBook", message: Data(#"{"key":"book"}"#.utf8)) { output.append(event) }
        guard case .text(let json) = output.first else { return XCTFail("Missing search array") }
        let books = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(books.first?["bookUrl"] as? String, "https://book.test/1")
        XCTAssertEqual(books.first?["name"] as? String, "小说")
        XCTAssertEqual(books.first?["author"] as? String, "作者")
        XCTAssertEqual(books.first?["origin"] as? String, "source")
        XCTAssertEqual(output.last, .close(1000, "Search finish"))
    }

    func testHandshakeRequiresHost() {
        let request = WebHttpRequest(method: "GET", target: "/searchBook", headers: [
            "Connection": "Upgrade", "Upgrade": "websocket", "Sec-WebSocket-Version": "13",
            "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ=="])
        XCTAssertThrowsError(try WebSocketHandshake.response(request))
    }

    func testReviewSearchSnapshotsMergeRankAndEmptyBatch() async throws {
        func book(_ name: String, _ author: String, _ kind: String?, _ origin: String) -> SearchBook {
            var value = SearchBook(now: 0)
            value.name = name; value.author = author; value.kind = kind; value.origin = origin
            return value
        }
        let other = book("其他", "作者", nil, "a")
        let contains = book("小说合集", "作者", nil, "a")
        let tag = book("分类书", "作者", "小说", "a")
        let exact = book("小说", "作者", nil, "a")
        let author = book("作者书", "小说", nil, "a")
        let duplicate = book("作者书", "小说", nil, "b")
        let batches = [[other, contains, tag, exact, author], [duplicate], []]
        let routes = WebSocketRoutes(bookDebug: { _, _ in nil }, rssDebug: { _ in nil }, search: { _ in
            AsyncThrowingStream { c in batches.forEach { c.yield($0) }; c.finish() }
        })
        var snapshots: [[SearchBook]] = []
        for await event in routes.events(path: "/searchBook", message: Data(#"{"key":"小说"}"#.utf8)) {
            if case .text(let json) = event { snapshots.append(try JSONDecoder().decode([SearchBook].self, from: Data(json.utf8))) }
        }
        XCTAssertEqual(snapshots.map { $0.map(\.name) }, [
            ["小说", "作者书", "分类书", "小说合集", "其他"],
            ["作者书", "小说", "分类书", "小说合集", "其他"],
            ["作者书", "小说", "分类书", "小说合集", "其他"]])
        XCTAssertEqual(snapshots[1].first?.origin, "a")
    }

    func testReviewSearchScopeGroupsSingleSourceAndFallback() {
        func source(_ url: String, _ group: String, _ enabled: Bool, _ order: Int) -> BookSource {
            var source = BookSource()
            source.bookSourceUrl = url; source.bookSourceGroup = group; source.enabled = enabled; source.customOrder = order
            return source
        }
        let sources = [source("a", " 甲；乙 ", true, 2), source("b", "乙", true, 1), source("c", "甲", false, 0)]
        func urls(_ scope: String) -> [String?] { WebSocketSearchOptions(scope: scope).select(sources).map(\.bookSourceUrl) }
        XCTAssertEqual(urls(""), ["b", "a"])
        XCTAssertEqual(urls("甲"), ["a"])
        XCTAssertEqual(urls("甲,乙"), ["b", "a"])
        XCTAssertEqual(urls("单源::c"), ["c"])
        XCTAssertEqual(urls("丢失分组"), ["b", "a"])
        XCTAssertEqual(urls("丢失::missing"), ["b", "a"])
    }

    func testReviewConcurrentSearchAndWholeSourceTimeout() async throws {
        let slow = ReviewSocketGate(), timeout = ReviewSocketGate()
        let fastFinished = expectation(description: "fast source is not blocked")
        let allFinished = expectation(description: "timeout finishes source")
        let sources = ["slow", "fast"].map { url -> BookSource in
            var source = BookSource(); source.bookSourceUrl = url; return source
        }
        let batches = WebSocketSearch.batches(sources: sources, key: "小说", options: .init(threadCount: 2), search: { source, _, _ in
            if source.bookSourceUrl == "slow" { await slow.wait() }
            var book = SearchBook(now: 0); book.name = source.bookSourceUrl
            return [book]
        }, sleep: { nanoseconds in
            XCTAssertEqual(nanoseconds, 30_000_000_000)
            await timeout.wait()
            try Task.checkCancellation()
        })
        let consumer = Task { () throws -> [String?] in
            var names: [String?] = []
            for try await batch in batches {
                names += batch.map(\.name)
                if batch.first?.name == "fast" { fastFinished.fulfill() }
            }
            allFinished.fulfill()
            return names
        }
        await fulfillment(of: [fastFinished], timeout: 2)
        await timeout.open()
        await fulfillment(of: [allFinished], timeout: 2)
        await slow.open()
        let names = try await consumer.value
        XCTAssertEqual(names, ["fast"])
    }

    func testReviewPrecisionSearchUsesNameAuthorAndKind() async throws {
        let database = try AppDatabase.inMemory()
        let api = WebApi(database: database)
        let saved = await api.handle(.init(method: "POST", target: "/saveBookSource", body: Data(#"{"bookSourceUrl":"https://source.test","bookSourceName":"测试","searchUrl":"/search","ruleSearch":{"bookList":"a","name":"span@text","author":"i@text","kind":"b@text","bookUrl":"href"}}"#.utf8)))
        XCTAssertEqual(try (JSONSerialization.jsonObject(with: saved.body) as? [String: Any])?["isSuccess"] as? Bool, true)
        for precise in [true, false] {
            let routes = WebSocketRoutes.live(database: database, client: ReviewPrecisionHTTP(), searchOptions: { .init(precisionSearch: precise) })
            var books: [SearchBook] = []
            for await event in routes.events(path: "/searchBook", message: Data(#"{"key":"小说"}"#.utf8)) {
                if case .text(let json) = event { books = try JSONDecoder().decode([SearchBook].self, from: Data(json.utf8)) }
            }
            XCTAssertEqual(books.map(\.name), precise ? ["小说", "分类书", "作者书"] : ["小说", "分类书", "作者书", "其他"])
        }
    }

    func testReviewRSSDebugStageAndFieldLogs() async throws {
        let database = try AppDatabase.inMemory()
        var source = RssSource(sourceUrl: "https://rss.test/list")
        source.ruleArticles = "a"; source.ruleTitle = "b@text"; source.rulePubDate = "time@text"
        source.ruleLink = "href"; source.ruleContent = "p@text"
        try await RssRepository(database: database).saveSources([source])
        let routes = WebSocketRoutes.live(database: database, client: ReviewRSSHTTP())
        var logs: [String] = []
        for await event in routes.events(path: "/rssSourceDebug", message: Data(#"{"tag":"https://rss.test/list"}"#.utf8)) {
            if case .text(let text) = event {
                logs.append(text.range(of: "] ").map { String(text[$0.upperBound...]) } ?? text)
            }
        }
        XCTAssertEqual(logs, ["︾开始解析", "≡获取成功:https://rss.test/list", "┌获取列表", "└列表大小:1",
                              "┌获取标题", "└标题", "┌获取时间", "└日期", "┌获取描述", "└描述规则为空，将会解析内容页",
                              "┌获取图片url", "└", "┌获取文章链接", "└https://rss.test/article", "︽列表页解析完成", "",
                              "︾开始解析内容页", "≡获取成功:https://rss.test/article", "正文", "︽内容页解析完成"])
    }

    func testReviewDecoderFailureIsTerminal() throws {
        var decoder = WebSocketFrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data([0x81, 0])))
        XCTAssertEqual(try decoder.append(WebSocketFrame(opcode: .ping).encoded(mask: [0, 0, 0, 0])), [])
    }

    func testReviewDefaultRSSFieldDiagnostics() throws {
        var logs: [String] = []
        let xml = "<rss><channel><item><title>标题</title><pubDate>日期</pubDate><description>简介</description><link>https://rss.test/article</link></item></channel></rss>"
        _ = try RssParser().parse(xml, source: RssSource(sourceUrl: "https://rss.test"), baseURL: "https://rss.test", debugLog: { logs.append($0) })
        XCTAssertEqual(logs, ["⇒列表规则为空, 使用默认规则解析", "┌获取标题", "└标题", "┌获取时间", "└日期",
                              "┌获取描述", "└简介", "┌获取图片url", "└null", "┌获取文章链接", "└https://rss.test/article"])
    }

    func testReviewSearchConcurrencyLimit() async throws {
        let release = ReviewSocketGate(), timeout = ReviewSocketGate(), probe = ReviewSocketConcurrency()
        let started = expectation(description: "configured slots started"); started.expectedFulfillmentCount = 2
        let sources = (0..<5).map { value -> BookSource in var source = BookSource(); source.bookSourceUrl = "\(value)"; return source }
        let batches = WebSocketSearch.batches(sources: sources, key: "key", options: .init(threadCount: 2), search: { _, _, _ in
            if await probe.enter() <= 2 { started.fulfill() }
            await release.wait()
            await probe.leave()
            return []
        }, sleep: { _ in await timeout.wait(); try Task.checkCancellation() })
        let consumer = Task { () throws -> Int in
            var count = 0
            for try await _ in batches { count += 1 }
            return count
        }
        await fulfillment(of: [started], timeout: 2)
        let firstWave = await probe.total
        XCTAssertEqual(firstWave, 2)
        await release.open()
        let count = try await consumer.value
        await timeout.open()
        let peak = await probe.peak
        XCTAssertEqual(count, 5)
        XCTAssertEqual(peak, 2)
    }
}

private actor ReviewSocketConcurrency {
    private var active = 0
    private(set) var total = 0
    private(set) var peak = 0
    func enter() -> Int {
        active += 1; total += 1; peak = max(peak, active)
        return total
    }
    func leave() { active -= 1 }
}

private struct ReviewRSSHTTP: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        let html = request.url.path == "/article" ? "<p>正文</p>" : "<a href='/article'><b>标题</b><time>日期</time></a>"
        return .init(status: 200, body: Data(html.utf8), finalURL: request.url)
    }
}

private struct ReviewPrecisionHTTP: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        let html = "<a href='/1'><span>小说</span><i>A</i></a><a href='/2'><span>作者书</span><i>小说作者</i></a><a href='/3'><span>分类书</span><b>小说分类</b></a><a href='/4'><span>其他</span><i>A</i><b>B</b></a>"
        return .init(status: 200, body: Data(html.utf8), finalURL: request.url)
    }
}

private actor ReviewSocketGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters; waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private struct SocketFakeHTTP: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        .init(status: 200, body: Data((request.url.host == "rss.test" ? "<rss><channel></channel></rss>" : "<html></html>").utf8), finalURL: request.url)
    }
}
