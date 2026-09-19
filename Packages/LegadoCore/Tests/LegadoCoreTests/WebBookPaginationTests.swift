import XCTest
@testable import LegadoCore

final class WebBookPaginationTests: XCTestCase {
    private func source() -> BookSource {
        var source = BookSource()
        source.bookSourceUrl = "https://pages.test"
        source.ruleToc = TocRule()
        source.ruleToc?.chapterList = "tag.b"
        source.ruleToc?.chapterName = "text"
        source.ruleToc?.chapterUrl = "data-url"
        source.ruleToc?.nextTocUrl = "tag.a@href"
        source.ruleContent = ContentRule()
        source.ruleContent?.content = "@js:var n=java.getString('tag.p@text');java.put('page'+n,n);n"
        source.ruleContent?.nextContentUrl = "tag.a@href"
        return source
    }

    private func book() -> Book {
        var book = Book(now: 0)
        book.bookUrl = "https://pages.test/book"
        book.tocUrl = "https://pages.test/1"
        return book
    }

    func testConcurrentPagesRespectLimitAndPreserveLinkOrder() async throws {
        for toc in [false, true] {
            let initial = expectation(description: "First two page requests")
            initial.expectedFulfillmentCount = 2
            let last = expectation(description: "Final page request")
            let client = ControlledPages { path in
                if path == "/2" || path == "/3" { initial.fulfill() }
                if path == "/4" { last.fulfill() }
            }
            let web = WebBook(source: source(), client: client, configuration: .init(threadCount: 2))
            let task = Task { () throws -> [String] in
                if toc {
                    var book = book()
                    return try await web.chapterList(book: &book).compactMap(\.title)
                }
                var chapter = BookChapter()
                chapter.url = "https://pages.test/1"
                let result = try await web.content(book: book(), chapter: chapter)
                let variables = try JsChapterBinding(result.chapter).store.variables
                for index in 1...4 { XCTAssertEqual(variables["page" + String(index)], String(index)) }
                return result.rawContent.components(separatedBy: "\n")
            }
            await fulfillment(of: [initial], timeout: 5)
            await client.complete("/3")
            await fulfillment(of: [last], timeout: 5)
            await client.complete("/4")
            await client.complete("/2")
            let result = try await task.value
            XCTAssertEqual(result, ["1", "2", "3", "4"])
            let peak = await client.maximumActive
            XCTAssertEqual(peak, 2)
        }
    }

    func testCancellingPaginationCancelsEveryActivePage() async throws {
        let initial = expectation(description: "Active page requests")
        initial.expectedFulfillmentCount = 2
        let client = ControlledPages { path in if path == "/2" || path == "/3" { initial.fulfill() } }
        let web = WebBook(source: source(), client: client, configuration: .init(threadCount: 2))
        let task = Task {
            var book = book()
            return try await web.chapterList(book: &book)
        }
        await fulfillment(of: [initial], timeout: 5)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let active = await client.activeCount
        let paths = await client.paths
        XCTAssertEqual(active, 0)
        XCTAssertFalse(paths.contains("/4"))
    }
}

private actor ControlledPages: HttpClient {
    private var pending: [String: CheckedContinuation<HttpResponse, Error>] = [:]
    private let started: @Sendable (String) -> Void
    private(set) var maximumActive = 0
    private(set) var paths: [String] = []
    var activeCount: Int { pending.count }

    init(started: @escaping @Sendable (String) -> Void) { self.started = started }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        try Task.checkCancellation()
        let path = request.url.path
        paths.append(path)
        if path == "/1" { return response(path) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                pending[path] = continuation
                maximumActive = max(maximumActive, pending.count)
                started(path)
            }
        } onCancel: { Task { await self.cancel(path) } }
    }

    func complete(_ path: String) { pending.removeValue(forKey: path)?.resume(returning: response(path)) }
    private func cancel(_ path: String) { pending.removeValue(forKey: path)?.resume(throwing: CancellationError()) }
    private func response(_ path: String) -> HttpResponse {
        let number = String(path.dropFirst())
        let links = path == "/1" ? "<a href='/2'></a><a href='/3'></a><a href='/4'></a>" : "<a href='/ignored'></a>"
        let body = "<p>" + number + "</p><b data-url='/chapter" + number + "'>" + number + "</b>" + links
        return HttpResponse(status: 200, body: Data(body.utf8), finalURL: URL(string: "https://pages.test" + path)!)
    }
}
