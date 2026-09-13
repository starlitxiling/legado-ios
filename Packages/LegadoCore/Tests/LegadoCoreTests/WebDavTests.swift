import XCTest
@testable import LegadoCore

final class WebDavTests: XCTestCase {
    let root = URL(string: "https://dav.example.invalid/dav/")!
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:multistatus xmlns:d="DAV:" xmlns:s="http://www.w3.org/2001/XMLSchema">
      <d:response><d:href>/dav/legado/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
      <d:response><d:href>/dav/legado/backup2024-01-02.zip</d:href><d:propstat><d:prop><d:getcontentlength>123</d:getcontentlength><d:getlastmodified>Tue, 02 Jan 2024 03:04:06 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat><d:propstat><d:prop><d:displayname>bad</d:displayname></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response>
      <d:response><d:href>/dav/legado/legado2023.zip</d:href><d:propstat><d:prop><d:displayname>legado2023.zip</d:displayname></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
      <d:response><d:href>/dav/legado/%E4%B8%AD%E6%96%87%20a%2Bb%25.zip</d:href><d:propstat><d:prop><d:displayname>%E4%B8%AD%E6%96%87%20a+b%25.zip</d:displayname></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
    </d:multistatus>
    """

    func testReplayListDownloadAndImport() async throws {
        let replay = ReplayHttpClient()
        let directory = root.appendingPathComponent("legado", isDirectory: true)
        await replay.enqueue(url: directory, method: "PROPFIND", response: HttpResponse(status: 207, body: Data(xml.utf8), finalURL: directory))
        let client = WebDavClient(baseURL: root, username: "user", password: "pass", httpClient: replay)
        let source = WebDavBackupSource(client: client)
        let files = try await source.listBackups()
        XCTAssertEqual(files.map(\.displayName), ["backup2024-01-02.zip", "legado2023.zip"])
        let data = try Data(contentsOf: BackupTests.fixtures.appendingPathComponent("backup2024-01-02.zip"))
        await replay.enqueue(url: files[0].url, response: HttpResponse(status: 200, body: data, finalURL: files[0].url))
        let database = try AppDatabase.inMemory()
        let report = try await source.restore(files[0], importer: BackupImporter(database: database, localDeviceID: "local", now: { 0 }))
        XCTAssertEqual(report.importedCounts["bookshelf.json"], 1)
        let requests = await replay.requests
        XCTAssertEqual(requests.map(\.method), ["PROPFIND", "GET"])
        XCTAssertEqual(requests[0].headers["Depth"], "1")
        XCTAssertEqual(requests[0].headers["Authorization"], "Basic dXNlcjpwYXNz")
    }

    func testNamespacesEncodedHrefAndDefaultNamespace() throws {
        let files = try WebDavXMLParser.parse(Data(xml.utf8), relativeTo: root)
        XCTAssertEqual(files.count, 4)
        XCTAssertTrue(files[0].isDirectory)
        XCTAssertEqual(files[1].size, 123)
        XCTAssertEqual(files[1].lastModified?.timeIntervalSince1970, 1704164646)
        XCTAssertEqual(files[3].displayName, "中文 a+b%.zip")
        XCTAssertTrue(files[3].url.absoluteString.contains("%2B"))
        let plain = "<multistatus xmlns=\"DAV:\"><response><href>/dav/x</href><propstat><prop><getcontenttype>httpd/unix-directory</getcontenttype></prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>"
        XCTAssertTrue(try WebDavXMLParser.parse(Data(plain.utf8), relativeTo: root)[0].isDirectory)
        XCTAssertThrowsError(try WebDavXMLParser.parse(Data("<broken>".utf8), relativeTo: root))
    }

    func testPathEncodingAndForeignOriginRejection() async throws {
        let replay = ReplayHttpClient()
        let client = WebDavClient(baseURL: root, username: "u", password: "p", httpClient: replay)
        XCTAssertEqual(try client.url(path: "中文 a+b%/#?.zip").absoluteString,
                       "https://dav.example.invalid/dav/%E4%B8%AD%E6%96%87%20a+b%25/%23%3F.zip")
        do {
            _ = try await client.get(URL(string: "https://foreign.invalid/file")!)
            XCTFail("应拒绝跨源凭据发送")
        } catch WebDavError.foreignOrigin {}
        let requests = await replay.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testExistsPutMkcolUseOnlyReplay() async throws {
        let replay = ReplayHttpClient()
        let client = WebDavClient(baseURL: root, username: "u", password: "p", httpClient: replay)
        let file = try client.url(path: "file")
        for (method, status) in [("PROPFIND", 404), ("PUT", 201), ("MKCOL", 201), ("GET", 401)] {
            await replay.enqueue(url: file, method: method, response: HttpResponse(status: status, finalURL: file))
        }
        let exists = try await client.exists(file)
        XCTAssertFalse(exists)
        try await client.put(Data("body".utf8), to: file, overwrite: false)
        try await client.mkcol(file)
        do { _ = try await client.get(file); XCTFail("应报告 HTTP 错误") }
        catch WebDavError.httpStatus(let status) { XCTAssertEqual(status, 401) }
        let requests = await replay.requests
        XCTAssertEqual(requests[0].headers["Depth"], "0")
        XCTAssertEqual(requests[1].headers["If-None-Match"], "*")
        XCTAssertEqual(requests[1].body, Data("body".utf8))
    }

    func testDatedDeviceSuffixSortAndTemporaryDownload() async throws {
        let replay = ReplayHttpClient()
        let client = WebDavClient(baseURL: root, username: "u", password: "p", httpClient: replay)
        let directory = try client.url(path: "legado/")
        let names = ["backup2024-01-01-new.zip", "backup2024-01-02-old.zip", "other.zip"]
        let responses = names.map { name in
            "<response><href>/dav/legado/\(name)</href><propstat><prop><resourcetype/><getlastmodified>Wed, 01 Jan 2025 00:00:00 GMT</getlastmodified></prop><status>HTTP/1.1 200 OK</status></propstat></response>"
        }.joined()
        let data = Data("<multistatus xmlns=\"DAV:\">\(responses)</multistatus>".utf8)
        await replay.enqueue(url: directory, method: "PROPFIND", response: HttpResponse(status: 207, body: data, finalURL: directory))
        let source = WebDavBackupSource(client: client)
        let files = try await source.listBackups()
        XCTAssertEqual(files.map(\.displayName), [names[1], names[0]])
        await replay.enqueue(url: files[0].url, response: HttpResponse(status: 200, body: Data("zip".utf8), finalURL: files[0].url))
        let temporary = try await source.downloadToTemporaryFile(files[0])
        defer { try? FileManager.default.removeItem(at: temporary) }
        XCTAssertEqual(try Data(contentsOf: temporary), Data("zip".utf8))
    }
}
