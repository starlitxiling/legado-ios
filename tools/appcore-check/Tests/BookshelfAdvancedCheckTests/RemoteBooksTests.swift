import XCTest
import LegadoCore
@testable import BookshelfAdvancedCheck

@MainActor
final class RemoteBooksTests: XCTestCase {
    func testListingFiltersSelfAndUnsupportedFilesAndSortsDirectoriesFirst() async throws {
        let db = try AppDatabase.inMemory(), client = ReplayHttpClient()
        let url = URL(string: "https://dav.test/books/")!
        let xml = """
        <d:multistatus xmlns:d="DAV:">
        <d:response><d:href>/books/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
        <d:response><d:href>/books/Book.txt</d:href><d:propstat><d:prop><d:displayname>Book.txt</d:displayname></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
        <d:response><d:href>/books/image.png</d:href><d:propstat><d:prop><d:displayname>image.png</d:displayname></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
        <d:response><d:href>/books/Folder/</d:href><d:propstat><d:prop><d:displayname>Folder</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
        </d:multistatus>
        """
        await client.enqueue(url: url, method: "PROPFIND", response: .init(status: 207, body: Data(xml.utf8), finalURL: url))
        let endpoint = RemoteBooksEndpoint(client: WebDavClient(baseURL: url, username: "user", password: "pass", httpClient: client), root: url, serverID: 9)
        let model = RemoteBooksModel(database: db, endpoint: endpoint)
        await model.load()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.files.map(\.displayName), ["Folder", "Book.txt"])
        XCTAssertEqual(model.directories, [url])
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.method), ["PROPFIND"])
    }

    func testRemoteImportDownloadsParsesAndKeepsServerIdentityWithoutRemoteWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try AppDatabase.inMemory(), client = ReplayHttpClient()
        let url = URL(string: "https://dav.test/books/Book.txt")!
        await client.enqueue(url: url, response: .init(status: 200, body: Data("Sample body".utf8), finalURL: url))
        let endpoint = RemoteBooksEndpoint(client: WebDavClient(baseURL: url, username: "user", password: "pass", httpClient: client), root: url.deletingLastPathComponent(), serverID: 9)
        let model = RemoteBooksModel(database: db, endpoint: endpoint, destination: directory)
        let file = WebDavFile(url: url, displayName: "Book.txt")
        await model.importBook(file, groupID: 2)
        XCTAssertNil(model.errorMessage)
        let saved = try await BookshelfRepository(database: db).all()
        let book = try XCTUnwrap(saved.first)
        XCTAssertTrue(book.origin.hasPrefix("webDav::https://dav.test/books/Book.txt"))
        XCTAssertEqual(UrlOptions.parse(String(book.origin.dropFirst("webDav::".count))).options.serverID, 9)
        XCTAssertEqual(book.group, 2)
        let chapters = try await ChapterRepository(database: db).list(bookUrl: book.bookUrl)
        XCTAssertFalse(chapters.isEmpty)
        let entity = try DiscoveryStorage.book(book)
        XCTAssertTrue(LocalBook.isLocal(entity))
        XCTAssertNotNil(LocalBook.fileURL(entity))
        await model.importBook(file, groupID: 4)
        let updated = try await BookshelfRepository(database: db).get(bookUrl: book.bookUrl)
        XCTAssertEqual(updated?.group, 6)
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.method), ["GET"])
        await model.importBook(WebDavFile(url: url, displayName: "../Book.txt"), groupID: 0)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isImporting)
    }
}
