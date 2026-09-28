import XCTest
import LegadoCore
@testable import ReaderCheck

@MainActor
final class ReaderErrorPresentationTests: XCTestCase {
    func testCancelledTaskRequestHasNoPresentedError() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await CancelledReaderClient().send(HttpRequest(url: URL(string: "https://cancel.test")!))
                XCTFail("Expected cancelled request")
            } catch {
                XCTAssertTrue(Task.isCancelled)
                XCTAssertEqual((error as? URLError)?.code, .cancelled)
                XCTAssertTrue(error.isCancellation)
                XCTAssertNil(error.presentation(operation: "Load chapter"))
            }
        }
        await task.value
    }

    func testPaginationErrorsAreLocalized() {
        XCTAssertTrue(PaginationError.invalidPageSize.localizedDescription.contains("页面尺寸"))
        XCTAssertTrue(PaginationError.noVisibleCharacters.localizedDescription.contains("文字"))
    }

    func testOfflineChapterFailureNamesBookAndChapter() async throws {
        let database = try AppDatabase.inMemory()
        var book = BookRow(); book.bookUrl = "https://offline.test/book"; book.origin = "https://offline.test"
        book.name = "Offline book"
        try await BookshelfRepository(database: database).insert(book)
        var chapter = BookChapterRow(); chapter.bookUrl = book.bookUrl; chapter.url = book.bookUrl + "/1"; chapter.title = "Chapter one"
        try await ChapterRepository(database: database).insert(chapter)
        var source = BookSourceRow(); source.bookSourceUrl = book.origin; source.bookSourceName = "Offline source"
        source.ruleContent = #"{"content":"body@text"}"#
        try await BookSourceRepository(database: database).insert(source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = ReaderViewModel(database: database, client: OfflineReaderClient(), cacheDirectory: directory, preDownloadCount: { 0 })
        await model.load(bookURL: book.bookUrl)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.errorMessage?.contains("正文加载失败") == true)
        XCTAssertTrue(model.errorMessage?.contains("Offline book") == true)
        XCTAssertTrue(model.errorMessage?.contains("Chapter one") == true)
        XCTAssertTrue(model.errorMessage?.contains("网络") == true)
        XCTAssertEqual(model.userError?.actions, [.retry, .changeSource, .manageSources, .back])
        model.dismissError()
        XCTAssertNil(model.userError)
        await model.close()
    }
}

private struct OfflineReaderClient: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse { throw URLError(.notConnectedToInternet) }
}

private struct CancelledReaderClient: HttpClient {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        XCTAssertTrue(Task.isCancelled)
        throw URLError(.cancelled)
    }
}
