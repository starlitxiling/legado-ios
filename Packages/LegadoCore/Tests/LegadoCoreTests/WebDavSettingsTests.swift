import XCTest
@testable import LegadoCore

private struct BoundedReplay: ResponseLimitedHttpClient {
    let replay: ReplayHttpClient
    func send(_ request: HttpRequest) async throws -> HttpResponse { try await replay.send(request) }
    func send(_ request: HttpRequest, maximumResponseBytes: Int) async throws -> HttpResponse {
        let response = try await replay.send(request)
        guard response.body.count <= maximumResponseBytes else { throw WebDavError.responseTooLarge }
        return response
    }
}

final class WebDavSettingsTests: XCTestCase {
    private func client(_ replay: ReplayHttpClient) -> WebDavClient {
        WebDavClient(baseURL: URL(string: "https://example.invalid/dav/")!, username: "u", password: "p", httpClient: BoundedReplay(replay: replay))
    }
    private func listing(_ href: String, name: String) -> Data {
        Data("<d:multistatus xmlns:d='DAV:'><d:response><d:href>\(href)</d:href><d:propstat><d:prop><d:displayname>\(name)</d:displayname><d:getlastmodified>Thu, 01 Jan 1970 00:00:02 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>".utf8)
    }
    func testStartupListsOnceAndOnlyDownloadsNewerForwardProgress() async throws {
        let replay = ReplayHttpClient()
        let dav = self.client(replay)
        var book = BookRow(); book.name = "book"; book.author = "author"; book.syncTime = 1000
        var advanced = book; advanced.durChapterIndex = 3; advanced.durChapterTime = 1500
        let directory = try dav.url(path: "legado/bookProgress/")
        let file = try dav.url(path: "legado/bookProgress/book_author.json")
        await replay.enqueue(url: directory, method: "PROPFIND", response: HttpResponse(status: 207, body: listing(file.path, name: "book_author.json"), finalURL: directory))
        await replay.enqueue(url: file, response: HttpResponse(status: 200, body: try JSONEncoder().encode(BookProgress(book: advanced)), finalURL: file))
        var newer = book; newer.syncTime = 3000
        let result = try await BookProgressSync(client: dav).downloadAll([book, newer], now: 4000)
        XCTAssertEqual(result.map(\.durChapterIndex), [3, 0])
        XCTAssertEqual(result.map(\.syncTime), [4000, 3000])
        let requests = await replay.requests
        XCTAssertEqual(requests.map(\.method), ["PROPFIND", "GET"])
    }
    func testReaderPlusOffersAheadProgressWithoutUploadingOrWritingIt() async throws {
        let replay = ReplayHttpClient()
        let client = self.client(replay)
        var book = BookRow(); book.name = "book"; book.syncTime = 999999
        var advanced = book; advanced.durChapterIndex = 4
        let file = try client.url(path: "legado/bookProgress/book_.json")
        await replay.enqueue(url: file, response: HttpResponse(status: 200, body: try JSONEncoder().encode(BookProgress(book: advanced)), finalURL: file))
        let result = try await BookProgressSync(client: client).synchronizeReading(book, now: 4000)
        XCTAssertEqual(result.remoteProgress?.durChapterIndex, 4)
        XCTAssertEqual(result.book.durChapterIndex, 0)
        let requests = await replay.requests
        XCTAssertEqual(requests.map(\.method), ["GET"])
    }
    func testMissingLocalBookRestoresAndBindsWithoutChangingIdentity() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/webdav-local-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let replay = ReplayHttpClient()
        let client = self.client(replay)
        var book = BookRow(); book.bookUrl = root.appendingPathComponent("old/book.txt").absoluteString; book.originName = "book.txt"; book.type = 264
        let restorer = WebDavLocalBookRestore(client: client, destination: root.appendingPathComponent("books"))
        let disabled = try await restorer.restore(book, enabled: false)
        XCTAssertEqual(disabled.bookUrl, book.bookUrl)
        let disabledRequests = await replay.requests
        XCTAssertTrue(disabledRequests.isEmpty)
        let directory = try client.url(path: "legado/books/")
        let file = try client.url(path: "legado/books/book.txt")
        await replay.enqueue(url: directory, method: "PROPFIND", response: HttpResponse(status: 207, body: listing(file.path, name: "book.txt"), finalURL: directory))
        await replay.enqueue(url: file, response: HttpResponse(status: 200, body: Data("正文".utf8), finalURL: file))
        let restored = try await restorer.restore(book, enabled: true)
        XCTAssertEqual(restored.bookUrl, book.bookUrl)
        let entity = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(LocalBook.fileURL(entity)), encoding: .utf8), "正文")
        _ = try await restorer.restore(restored, enabled: true)
        let requests = await replay.requests
        XCTAssertEqual(requests.map(\.method), ["PROPFIND", "GET"])
    }
}

extension WebDavSettingsTests {
    func testReadingActionRespectsBothSettingsAndExitBranch() {
        XCTAssertEqual(BookProgressSync.readingAction(syncEnabled: false, plusEnabled: true, exiting: true), .none)
        XCTAssertEqual(BookProgressSync.readingAction(syncEnabled: false, plusEnabled: true, exiting: false), .none)
        XCTAssertEqual(BookProgressSync.readingAction(syncEnabled: true, plusEnabled: false, exiting: false), .none)
        XCTAssertEqual(BookProgressSync.readingAction(syncEnabled: true, plusEnabled: true, exiting: false), .synchronize)
        XCTAssertEqual(BookProgressSync.readingAction(syncEnabled: true, plusEnabled: true, exiting: true), .synchronize)
        XCTAssertEqual(BookProgressSync.readingAction(syncEnabled: true, plusEnabled: false, exiting: true), .upload)
    }
    func testReadingSyncUploadsWhenRemoteMissingOrBehindAndDoesNothingWhenEqual() async throws {
        for position in [-1, 0, 1] {
            let replay = ReplayHttpClient()
            let dav = self.client(replay)
            var book = BookRow(); book.name = "book"; book.durChapterIndex = 1
            let file = try dav.url(path: "legado/bookProgress/book_.json")
            var remote = book; remote.durChapterIndex = position
            await replay.enqueue(url: file, response: HttpResponse(status: position == -1 ? 404 : 200, body: try JSONEncoder().encode(BookProgress(book: remote)), finalURL: file))
            if position < 1 {
                for directory in ["legado/", "legado/bookProgress/"] {
                    let url = try dav.url(path: directory)
                    await replay.enqueue(url: url, method: "PROPFIND", response: HttpResponse(status: 207, finalURL: url))
                }
                await replay.enqueue(url: file, method: "PUT", response: HttpResponse(status: 201, finalURL: file))
            }
            let result = try await BookProgressSync(client: dav).synchronizeReading(book, now: 5000)
            XCTAssertNil(result.remoteProgress)
            XCTAssertEqual(result.book.syncTime, position < 1 ? 5000 : 0)
            let requests = await replay.requests
            XCTAssertEqual(requests.filter { $0.method == "PUT" }.count, position < 1 ? 1 : 0)
        }
    }
}

extension WebDavSettingsTests {
    func testUnrelatedOnlineBookWithSerializedReadConfigNeverRequiresLocalDecoding() async throws {
        let replay = ReplayHttpClient()
        var book = BookRow(); book.origin = "https://source.invalid"; book.bookUrl = "https://source.invalid/book"
        book.readConfig = "{\"reverseToc\":true}"
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/unused-local-restore")
        let result = try await WebDavLocalBookRestore(client: client(replay), destination: directory).restore(book, enabled: true)
        XCTAssertEqual(result.readConfig, book.readConfig)
        let requests = await replay.requests
        XCTAssertTrue(requests.isEmpty)
    }
}
