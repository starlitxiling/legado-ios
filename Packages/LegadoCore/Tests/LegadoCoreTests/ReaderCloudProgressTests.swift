import XCTest
@testable import LegadoCore

final class ReaderCloudProgressTests: XCTestCase {
    func testExplicitPullCanReturnEarlierPositionWithoutUploading() async throws {
        let client = ReplayHttpClient()
        let base = URL(string: "https://dav.test/")!
        let url = URL(string: "https://dav.test/legado/bookProgress/Book_Author.json")!
        var book = BookRow(); book.name = "Book"; book.author = "Author"; book.durChapterIndex = 10
        var remote = BookProgress(book: book); remote.durChapterIndex = 2
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: try JSONEncoder().encode(remote), finalURL: url))
        let sync = BookProgressSync(client: WebDavClient(baseURL: base, username: "test", password: "test", httpClient: client))
        let result = try await sync.pull(book)
        XCTAssertEqual(result, remote)
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.method), ["GET"])
        remote.author = "Other"
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: try JSONEncoder().encode(remote), finalURL: url))
        do { _ = try await sync.pull(book); XCTFail("Foreign progress must be rejected") }
        catch { XCTAssertEqual(error as? BookProgressSyncError, .identityMismatch) }
    }
}
