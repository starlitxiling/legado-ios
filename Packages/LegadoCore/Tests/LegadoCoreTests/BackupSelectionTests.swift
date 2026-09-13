import XCTest
@testable import LegadoCore

final class BackupSelectionTests: XCTestCase {
    func testConfiguredUserAgentPreservesExplicitSourceHeader() async throws {
        let replay = ReplayHttpClient()
        let url = URL(string: "https://example.invalid/")!
        let client = PreferenceHttpClient(underlying: replay, userAgent: { "custom-agent" })
        await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url))
        await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url))
        _ = try await client.send(HttpRequest(url: url))
        _ = try await client.send(HttpRequest(url: url, headers: ["user-agent": "source-agent"]))
        let requests = await replay.requests
        XCTAssertEqual(requests[0].headers["User-Agent"], "custom-agent")
        XCTAssertEqual(requests[1].headers["user-agent"], "source-agent")
        XCTAssertNil(requests[1].headers["User-Agent"])
    }
    func testSelectionControlsActualArchiveFiles() async throws {
        let database = try AppDatabase.inMemory()
        let selection = BackupSelection(values: ["backupSources": true, "backupCookies": false])
        let data = try await BackupExporter(database: database).export(selection: selection)
        let files = try BackupArchive(data: data).files
        XCTAssertNil(files["bookSource.json"])
        XCTAssertNil(files["rssSources.json"])
        XCTAssertNotNil(files["cookies.json"])
        XCTAssertNotNil(files["bookshelf.json"])
    }

    func testRestoreIgnoreFiltersPreferencesAndCookies() async throws {
        let database = try AppDatabase.inMemory()
        let data = try await BackupExporter(database: database).export(preferences: ["colorAccent": .int(42), "showRss": .boolean(false), "fontScale": .int(12)], includeSourceState: true)
        let report = try await BackupImporter(database: database, localDeviceID: "test").importArchive(data,
            selection: BackupSelection(values: ["themeConfig": true, "showRss": true, "ignoreCookies": true]))
        XCTAssertNil(report.preferences?["colorAccent"])
        XCTAssertNil(report.preferences?["showRss"])
        XCTAssertEqual(report.preferences?["fontScale"], .int(12))
        XCTAssertTrue(report.skippedFiles.contains("cookies.json"))
        XCTAssertFalse(report.importedFiles.contains("cookies.json"))
    }

    func testEverySelectionAndIgnoreDefault() {
        let defaults = BackupSelection()
        for key in BackupSelection.contentKeys {
            XCTAssertEqual(defaults.includes(key), !["backupCookies", "backupSourceVariables", "backupReadRecordCovers"].contains(key), key)
            XCTAssertFalse(BackupSelection(values: [key: true]).includes(key), key)
            XCTAssertTrue(BackupSelection(values: [key: false]).includes(key), key)
        }
        for key in BackupSelection.ignoreKeys { XCTAssertNil(defaults.values[key]) }
        let cases = ["readStyleSelect": "readConfig", "themeMode": "themeMode", "colorPrimaryNight": "themeConfig",
                     "coverShowName": "coverConfig", "bookshelfLayout": "bookshelfLayout", "showRss": "showRss", "threadCount": "threadCount"]
        for (key, group) in cases {
            XCTAssertTrue(defaults.allowsPreference(key), key)
            XCTAssertFalse(BackupSelection(values: [group: true]).allowsPreference(key), key)
        }
        XCTAssertTrue(BackupSelection(values: ["ignoreSourceVariables": true]).ignoresFile("runtimeSourceCache.json"))
        XCTAssertTrue(BackupSelection(values: ["readConfig": true]).ignoresFile("readConfig.json"))
    }

    func testRestoreIgnoreLocalBookSkipsOnlyLocalRows() async throws {
        let database = try AppDatabase.inMemory()
        var local = BookRow(); local.bookUrl = "local"; local.origin = "loc_book"; local.name = "本地书"
        var remote = BookRow(); remote.bookUrl = "https://example.invalid/book"; remote.origin = "https://example.invalid"; remote.name = "在线书"
        try await BookshelfRepository(database: database).upsert([local, remote])
        let data = try await BackupExporter(database: database).export()
        let restored = try AppDatabase.inMemory()
        _ = try await BackupImporter(database: restored, localDeviceID: "test").importArchive(data, selection: BackupSelection(values: ["localBook": true]))
        let rows = try await BookshelfRepository(database: restored).all()
        XCTAssertEqual(rows.map(\.name), ["在线书"])
    }
}

extension BackupSelectionTests {
    func testConfiguredUserAgentSurvivesURLBuilderAndExplicitNullRemainsOmitted() async throws {
        let replay = ReplayHttpClient()
        let url = URL(string: "https://example.invalid/user-agent")!
        let client = PreferenceHttpClient(underlying: replay, userAgent: { "configured-agent" })
        let sourceHeaders: [String?] = [nil, #"{"user-agent":"source-agent"}"#, #"{"USER-AGENT":"null"}"#,
            String(decoding: try JSONSerialization.data(withJSONObject: ["User-Agent": UrlRequestBuilder.defaultUserAgent]), as: UTF8.self)]
        for headers in sourceHeaders {
            await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url))
            _ = try await UrlRequestBuilder.execute(url: url.absoluteString, sourceHeaderJSON: headers, client: client)
        }
        let requests = await replay.requests
        XCTAssertEqual(requests[0].headers.httpHeader("User-Agent"), "configured-agent")
        XCTAssertEqual(requests[1].headers.httpHeader("User-Agent"), "source-agent")
        XCTAssertNil(requests[2].headers.httpHeader("User-Agent"))
        XCTAssertEqual(requests[3].headers.httpHeader("User-Agent"), UrlRequestBuilder.defaultUserAgent)
    }

    func testConfiguredUserAgentHonorsOptionPrecedenceBoundedAndPlainRequests() async throws {
        let replay = ReplayHttpClient()
        let url = URL(string: "https://example.invalid/user-agent-options")!
        let client = PreferenceHttpClient(underlying: replay, userAgent: { "configured-agent" })
        let options = try UrlOptions.fromJSON(#"{"headers":{"USER-agent":"null"}}"#)
        let suppressed = try UrlRequestBuilder.build(url: url.absoluteString, options: options, sourceHeaderJSON: #"{"User-Agent":"source-agent"}"#)
        for request in [suppressed, try UrlRequestBuilder.build(url: url.absoluteString), HttpRequest(url: url, headers: ["user-agent": "null"])] {
            await replay.enqueue(url: url, response: HttpResponse(status: 200, finalURL: url))
            _ = try await client.send(request, maximumResponseBytes: 100)
        }
        let requests = await replay.requests
        XCTAssertNil(requests[0].headers.httpHeader("User-Agent"))
        XCTAssertEqual(requests[1].headers.httpHeader("User-Agent"), "configured-agent")
        XCTAssertNil(requests[2].headers.httpHeader("User-Agent"))
        let standalone = try UrlRequestBuilder.build(url: url.absoluteString)
        XCTAssertNil(standalone.headers.httpHeader("User-Agent"))
        XCTAssertEqual(URLSessionHttpClient.urlRequest(standalone).value(forHTTPHeaderField: "User-Agent"), UrlRequestBuilder.defaultUserAgent)
    }
}

extension BackupSelectionTests {
    func testFinalTransportsApplyDefaultsAndNeverReinsertSuppressedUserAgent() async throws {
        let url = URL(string: "https://example.invalid/ua-final")!
        let plain = URLSessionHttpClient(protocolClasses: [UserAgentEchoProtocol.self])
        let bounded = BoundedURLSessionHttpClient(protocolClasses: [UserAgentEchoProtocol.self])
        let configured = PreferenceHttpClient(underlying: bounded, userAgent: { "configured-agent" })
        for client in [plain as any HttpClient, bounded, configured] {
            for (header, expected) in [(nil as String?, client is PreferenceHttpClient ? "configured-agent" : UrlRequestBuilder.defaultUserAgent),
                                       (#"{"User-Agent":"null"}"#, "<none>"), (#"{"User-Agent":"source"}"#, "source")] {
                let request = try UrlRequestBuilder.build(url: url.absoluteString, sourceHeaderJSON: header)
                let response = try await client.send(request)
                XCTAssertEqual(String(decoding: response.body, as: UTF8.self), expected)
            }
        }
    }
}

private final class UserAgentEchoProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((request.value(forHTTPHeaderField: "User-Agent") ?? "<none>").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
