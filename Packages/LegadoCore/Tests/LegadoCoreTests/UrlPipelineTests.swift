import XCTest
@testable import LegadoCore

final class UrlPipelineTests: XCTestCase {
    func testKotlinPagePatternAndBounds() throws {
        let engine = JsEngine(httpClient: ReplayHttpClient())
        func rule(_ value: String, page: Int) throws -> String {
            try AnalyzeUrlExecutor(value, engine: engine, bindings: ["page": page]).ruleURL
        }
        XCTAssertEqual(try rule("https://page.test/<one,two>", page: 99), "https://page.test/two")
        XCTAssertEqual(try rule("https://page.test/<>", page: 1), "https://page.test/")
        XCTAssertEqual(try rule("https://page.test/<a<b,c>", page: 1), "https://page.test/a<b")
        XCTAssertEqual(try rule("https://page.test/<a\nb,c>", page: 1), "https://page.test/<a\nb,c>")
        XCTAssertEqual(try rule("https://page.test/<　a　,b>", page: 1), "https://page.test/　a　")
        XCTAssertEqual(try rule("https://page.test/plain", page: 0), "https://page.test/plain")
        XCTAssertThrowsError(try rule("https://page.test/<a,b>", page: 0))
        XCTAssertThrowsError(try rule("https://page.test/<a,b>", page: -1))
    }

    func testMultipartByteExactBodyAndQuotedNames() throws {
        let form = try MultipartBody(json: #"{"tag":"value","f\"\r\n":"fileRequest"}"#,
            fileName: "a\"\r\n.bin", file: Data([0, 255, 1]), contentType: "application/octet-stream", type: nil, boundary: "test-boundary")
        var expected = Data("--test-boundary\r\nContent-Disposition: form-data; name=\"tag\"\r\nContent-Length: 5\r\n\r\nvalue\r\n".utf8)
        expected.append(Data("--test-boundary\r\nContent-Disposition: form-data; name=\"f%22%0D%0A\"; filename=\"a%22%0D%0A.bin\"\r\nContent-Type: application/octet-stream\r\nContent-Length: 3\r\n\r\n".utf8))
        expected.append(Data([0, 255, 1]))
        expected.append(Data("\r\n--test-boundary--\r\n".utf8))
        XCTAssertEqual(form.data, expected)
        XCTAssertEqual(form.contentType, "multipart/mixed; boundary=test-boundary")
    }

    func testMultipartEmbeddedFileAndValidation() throws {
        let form = try MultipartBody(json: #"{"file":{"fileName":"a.txt","file":"text","contentType":"text/plain"},"number":1,"list":[true,"v"]}"#,
            fileName: "unused", file: Data(), contentType: "unused", type: "multipart/form-data", boundary: "b")
        let body = String(decoding: form.data, as: UTF8.self)
        XCTAssertTrue(body.contains("Content-Type: text/plain; charset=utf-8"))
        XCTAssertTrue(body.contains("\r\n\r\n1.0\r\n"))
        XCTAssertTrue(body.contains("\r\n\r\n[true, v]\r\n"))
        for json in ["[]", "{}", "broken", #"{"file":{"file":"x"}}"#] {
            XCTAssertThrowsError(try MultipartBody(json: json, fileName: "f", file: Data(), contentType: "text/plain", type: nil))
        }
        XCTAssertThrowsError(try MultipartBody(json: #"{"f":"fileRequest"}"#, fileName: "f", file: Data(),
            contentType: "text/plain\r\nX: injected", type: nil))
        XCTAssertThrowsError(try MultipartBody(json: #"{"f":"fileRequest"}"#, fileName: "f", file: Data(),
            contentType: "text/plain", type: "application/json"))
    }

    func testMultipartReadsLocalFileAndExplicitCharset() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("sample.bin")
        try Data([0, 255, 2]).write(to: file)
        let form = try MultipartBody(json: #"{"f":"fileRequest"}"#, fileName: "f", file: file, contentType: "application/octet-stream", type: nil)
        XCTAssertNotNil(form.data.range(of: Data([0, 255, 2])))
        let encoded = try MultipartBody(json: #"{"f":"fileRequest"}"#, fileName: "f", file: "caf\u{e9}", contentType: "text/plain; charset=iso-8859-1", type: nil)
        XCTAssertNotNil(encoded.data.range(of: Data([99, 97, 102, 233])))
    }

    func testUploadRemovesQueryRetriesAndUsesRoutingWithoutSourceHeaders() async throws {
        let client = ReplayHttpClient()
        let url = URL(string: "https://upload.test/path")!
        for status in [503, 201] {
            await client.enqueue(url: url, method: "POST", response: .init(status: status, body: Data("ok".utf8), finalURL: url))
        }
        let engine = JsEngine(httpClient: client)
        let executor = try AnalyzeUrlExecutor(#"https://upload.test/path?ignored=1,{"body":{"file":"fileRequest"},"type":"multipart/form-data","retry":1,"dnsIp":"192.0.2.8","headers":{"Authorization":"private"}}"#, engine: engine)
        let response = try await executor.upload(fileName: "f.bin", file: Data([0, 255]), contentType: "application/octet-stream")
        XCTAssertEqual(response.code, 201)
        XCTAssertEqual(response.body, "ok")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.body, requests.last?.body)
        XCTAssertEqual(requests.first?.url, url)
        XCTAssertEqual(requests.first?.hostAddresses["upload.test"], ["192.0.2.8"])
        XCTAssertNil(requests.first?.headers["Authorization"])
        XCTAssertTrue(requests.first?.headers["Content-Type"]?.hasPrefix("multipart/form-data;") == true)
    }

    func testOriginSelectsMatchingSourceThenFallsBackByDomainAndPattern() async throws {
        let database = try AppDatabase.inMemory()
        let repository = BookSourceRepository(database: database)
        var domain = BookSourceRow(); domain.bookSourceUrl = "https://book.test"
        var explicit = BookSourceRow(); explicit.bookSourceUrl = "specified"; explicit.enabled = false
        explicit.bookUrlPattern = #"https://book\.test/book.*"#
        var fallback = BookSourceRow(); fallback.bookSourceUrl = "fallback"; fallback.bookUrlPattern = #"https://other\.test/.*"#
        try await repository.upsert([domain, explicit, fallback])
        let specified = try await repository.sourceForBookURL(#"https://book.test/book,{"origin":"specified"}"#)
        XCTAssertEqual(specified?.bookSourceUrl, "specified")
        let mismatch = try await repository.sourceForBookURL(#"https://book.test/no-match,{"origin":"specified"}"#)
        XCTAssertEqual(mismatch?.bookSourceUrl, "https://book.test")
        let pattern = try await repository.sourceForBookURL("https://other.test/book")
        XCTAssertEqual(pattern?.bookSourceUrl, "fallback")
        let absent = try await repository.sourceForBookURL("https://missing.test/book")
        XCTAssertNil(absent)
    }

    func testServerIDSelectsStoredCredentialsAndPreservesOriginBoundary() async throws {
        let database = try AppDatabase.inMemory()
        let servers = ServerRepository(database: database)
        var server = Server(); server.id = 7
        try server.setWebDavConfig(.init(url: "https://dav.test/root/", username: "u", password: "p"))
        try await servers.upsert(server)
        let replay = ReplayHttpClient()
        let path = #"davs://dav.test/root/file.txt,{"serverID":7}"#
        let client = try await WebDavClient.fromPath(path, servers: servers, httpClient: replay)
        let url = try WebDavClient.remoteURL(path)
        await replay.enqueue(url: url, response: .init(status: 200, finalURL: url))
        _ = try await client.get(url)
        let requests = await replay.requests
        XCTAssertEqual(requests.first?.headers["Authorization"], "Basic dTpw")
        for (path, expected) in [
            ("davs://dav.test/root/file.txt", WebDavError.missingServerID),
            (#"davs://dav.test/root/file.txt,{"serverID":8}"#, .invalidServer(8)),
            (#"davs://foreign.test/root/file.txt,{"serverID":7}"#, .foreignOrigin)
        ] {
            do { _ = try await WebDavClient.fromPath(path, servers: servers, httpClient: replay); XCTFail("Expected credential selection failure") }
            catch let error as WebDavError { XCTAssertEqual(error, expected) }
        }
    }

    func testDAVCustomURLRestoresLocalBytesWithoutChangingBookIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        let servers = ServerRepository(database: database)
        var server = Server(); server.id = 9
        try server.setWebDavConfig(.init(url: "https://dav.test/books/", username: "u", password: "p"))
        try await servers.insert(server)
        let path = #"davs://dav.test/books/book.txt,{"serverID":9}"#
        let replay = ReplayHttpClient()
        let url = try WebDavClient.remoteURL(path)
        await replay.enqueue(url: url, response: .init(status: 200, body: Data("book bytes".utf8), finalURL: url))
        let client = try await WebDavClient.fromPath(path, servers: servers, httpClient: replay)
        var book = BookRow(); book.bookUrl = "portable-book-id"; book.origin = "webDav::" + path; book.originName = "book.txt"; book.type = 264
        let restored = try await WebDavLocalBookRestore(client: client, destination: root).restore(book, enabled: false)
        XCTAssertEqual(restored.bookUrl, book.bookUrl)
        let entity = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(restored))
        let file = try XCTUnwrap(LocalBook.fileURL(entity))
        XCTAssertEqual(try Data(contentsOf: file), Data("book bytes".utf8))
        _ = try await WebDavLocalBookRestore(client: client, destination: root).restore(restored, enabled: false)
        let requests = await replay.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testCustomURLKeepsAttributesAndRemovesNull() throws {
        let url = CustomUrl(#"https://custom.test/path, {"method":"POST","serverID":3,"headers":{"X":"v"}}"#)
        XCTAssertEqual(url.getUrl(), "https://custom.test/path")
        try url.putAttribute("serverID", 7).putAttribute("method", nil)
        XCTAssertEqual(UrlOptions.parse(url.description).options.serverID, 7)
        XCTAssertNil(try url.getAttr()["method"])
        XCTAssertEqual((try url.getAttr()["headers"] as? [String: String])?["X"], "v")
        let invalid = CustomUrl("https://custom.test/path,{broken")
        XCTAssertEqual(invalid.description, "https://custom.test/path")
        XCTAssertThrowsError(try url.putAttribute("bad", Date()))
    }
}
