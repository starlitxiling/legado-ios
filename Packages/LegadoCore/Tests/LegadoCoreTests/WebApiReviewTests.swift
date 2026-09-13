import XCTest
import ImageIO
@testable import LegadoCore

extension WebApiTests {
    func testReview1TokenRequiredAndHeaderOnly() async throws {
        let api = WebApi(database: try .inMemory())
        let router = HttpRouter(api: api, token: { "secret" })
        for headers in [[:], ["x-legado-token": "wrong"]] {
            let response = await router.handle(WebHttpRequest(method: "POST", target: "/saveBookSource?token=secret", headers: headers,
                body: Data(#"{"bookSourceUrl":"s","bookSourceName":"s"}"#.utf8)))
            XCTAssertEqual(try object(response)["errorMsg"] as? String, "Web 书源访问令牌未配置或不正确")
        }
        let allowed = await router.handle(WebHttpRequest(method: "POST", target: "/saveBookSource", headers: ["X-Legado-Token": "secret"],
            body: Data(#"{"bookSourceUrl":"s","bookSourceName":"s"}"#.utf8)))
        XCTAssertEqual(try object(allowed)["isSuccess"] as? Bool, true)
        let required = await router.handle(WebHttpRequest(method: "GET", target: "/getJsSourceApiTokenRequired"))
        XCTAssertEqual(try object(required)["data"] as? Bool, true)
    }

    func testReview2CORSAndPreflight() async throws {
        let router = HttpRouter(api: WebApi(database: try .inMemory()))
        for method in ["OPTIONS", "GET"] {
            let response = await router.handle(WebHttpRequest(method: method, target: "/getBookshelf", headers: ["origin": "https://reader.example"]))
            XCTAssertEqual(response.status, 200)
            XCTAssertTrue(String(decoding: response.encoded(), as: UTF8.self).contains("Access-Control-Allow-Origin: https://reader.example\r\n"))
            XCTAssertTrue(String(decoding: response.encoded(), as: UTF8.self).contains("Access-Control-Allow-Methods: GET, POST\r\n"))
        }
    }

    func testReview3ImagesAndSafeHTML() async throws {
        let directory = testDirectory("images")
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try AppDatabase.inMemory()
        var book = BookRow(); book.bookUrl = "book"; book.name = "book"
        try await BookshelfRepository(database: db).insert(book)
        let router = HttpRouter(api: WebApi(database: db, client: ReviewImageClient(), cacheDirectory: directory))
        for (path, width) in [("/cover?path=https%3A%2F%2Fimage.invalid%2Fone.png", 84), ("/image?url=book&path=https%3A%2F%2Fimage.invalid%2Fone.png&width=12", 12)] {
            let response = await router.handle(WebHttpRequest(method: "GET", target: path))
            XCTAssertEqual(response.contentType, "image/png")
            if let source = CGImageSourceCreateWithData(response.body as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                XCTAssertEqual(image.width, width)
            } else { XCTFail("Expected image bytes") }
        }
        let html = await router.handle(WebHttpRequest(method: "GET", target: "/"))
        XCTAssertTrue(String(decoding: html.body, as: UTF8.self).contains("renderContent"))
    }

    func testReview4ConfiguredBookshelfSort() async throws {
        let db = try AppDatabase.inMemory()
        var a = BookRow(); a.bookUrl = "a"; a.name = "A"; a.durChapterTime = 9; a.latestChapterTime = 1; a.order = 2
        var b = BookRow(); b.bookUrl = "b"; b.name = "B"; b.latestChapterTime = 8; b.order = 1
        try await BookshelfRepository(database: db).upsert([a, b])
        for (sort, expected) in [(0, "a"), (1, "b"), (2, "a"), (3, "b"), (9, "a")] {
            let response = await WebApi(database: db, bookshelfSort: { sort }).handle(WebHttpRequest(method: "GET", target: "/getBookshelf"))
            XCTAssertEqual((try object(response)["data"] as? [[String: Any]])?.first?["bookUrl"] as? String, expected)
        }
    }

    func testReview5PreviewPersistenceAndClearing() async throws {
        let api = WebApi(database: try .inMemory())
        for (body, expected) in [(#"{"id":42,"pattern":"a","previewText":"sample"}"#, "sample"),
                                 (#"{"id":42,"pattern":"a"}"#, "sample"),
                                 (#"{"id":42,"pattern":"b"}"#, nil)] as [(String, String?)] {
            _ = await api.handle(WebHttpRequest(method: "POST", target: "/saveReplaceRule", body: Data(body.utf8)))
            let result = try object(await api.handle(WebHttpRequest(method: "GET", target: "/getReplaceRules")))
            let values = try JSONSerialization.jsonObject(with: Data((result["data"] as! String).utf8)) as! [[String: Any]]
            XCTAssertEqual(values.first?["previewText"] as? String, expected)
        }
    }

    func testReview6RegexFailureIsSuccessfulData() async throws {
        let result = try object(await WebApi(database: try .inMemory()).handle(WebHttpRequest(method: "POST", target: "/testReplaceRule",
            body: Data(#"{"rule":{"pattern":"["},"text":"abc"}"#.utf8))))
        XCTAssertEqual(result["isSuccess"] as? Bool, true)
        XCTAssertFalse((result["data"] as? String ?? "").isEmpty)
    }

    func testReview8UploadAndDirectoryIndex() async throws {
        let directory = testDirectory("upload")
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try AppDatabase.inMemory()
        let router = HttpRouter(api: WebApi(database: db, booksDirectory: directory))
        let body = Data("--bound\r\nContent-Disposition: form-data; name=\"fileData\"; filename=\"book.txt\"\r\nContent-Type: text/plain\r\n\r\n第一章 开始\n正文内容\r\n--bound--\r\n".utf8)
        let response = await router.handle(WebHttpRequest(method: "POST", target: "/addLocalBook?fileName=book.txt", headers: ["content-type": "multipart/form-data; boundary=bound"], body: body))
        XCTAssertEqual(try object(response)["data"] as? Bool, true)
        let books = try await BookshelfRepository(database: db).all()
        XCTAssertEqual(books.count, 1)
        if let book = books.first { XCTAssertTrue(FileManager.default.fileExists(atPath: URL(string: book.bookUrl)!.path)) }
        let index = await router.handle(WebHttpRequest(method: "GET", target: "///"))
        XCTAssertEqual(index.status, 200)
        let invalid = await router.handle(WebHttpRequest(method: "POST", target: "/addLocalBook?fileName=..%2Fbad.txt", headers: ["content-type": "multipart/form-data; boundary=bound"], body: body))
        XCTAssertEqual(try object(invalid)["errorMsg"] as? String, "fileName 格式不正确")
    }

    private func object(_ response: WebHttpResponse) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }

    private func testDirectory(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/b14-\(name)-\(UUID().uuidString)")
    }
}

private struct ReviewImageClient: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6UAAAAABJRU5ErkJggg==")!
        return HttpResponse(status: 200, body: png, finalURL: request.url)
    }
}
