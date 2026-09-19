import XCTest
import LegadoCore
@testable import Legado

@MainActor
final class SourceRegressionTests: XCTestCase {
    private struct Candidate: Decodable {
        let id: String
        let keyword: String
        let source: BookSource
    }
    private struct Input: Decodable {
        let requiredPasses: Int
        let candidates: [Candidate]
    }
    private struct Report: Encodable {
        let id: String
        let passed: Bool
        let stage: String
        let searchCount: Int
        let chapterCount: Int
        let contentLength: Int
        let error: String?
    }
    private enum Failure: Error { case emptySearch, emptyToc, shortContent }

    func testConfiguredLiveSources() async throws {
        executionTimeAllowance = 360
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SourceRegression", isDirectory: true)
        let inputURL = directory.appendingPathComponent("input.json")
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw XCTSkip("Live source regression requires Documents/SourceRegression/input.json")
        }
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: inputURL))
        guard input.requiredPasses > 0, input.requiredPasses <= input.candidates.count else {
            return XCTFail("Invalid live regression threshold")
        }
        let webView = HeadlessWebViewScheduler(loader: HeadlessWebView(),
            isForeground: { await MainActor.run { HeadlessWebView.keyWindow != nil } })
        var reports: [Report] = []
        for candidate in input.candidates {
            var stage = "search", searchCount = 0, chapterCount = 0, contentLength = 0
            do {
                let web = WebBook(source: candidate.source, client: LiveSourceClient(),
                    configuration: .init(threadCount: 4, headlessWebView: webView))
                let found = try await web.search(key: candidate.keyword)
                searchCount = found.count
                guard let first = found.first else { throw Failure.emptySearch }
                stage = "info"
                var book = try await web.bookInfo(first)
                stage = "toc"
                let chapters = try await web.chapterList(book: &book, fromBookInfo: true)
                chapterCount = chapters.count
                guard let index = chapters.firstIndex(where: { !$0.isVolume }) else { throw Failure.emptyToc }
                stage = "content"
                let next = chapters.indices.contains(index + 1) ? chapters[index + 1].url : nil
                let content = try await web.content(book: book, chapter: chapters[index], nextChapterUrl: next, includeTitle: false)
                contentLength = content.text.filter { !$0.isWhitespace }.count
                guard contentLength >= 100 else { throw Failure.shortContent }
                reports.append(.init(id: candidate.id, passed: true, stage: "complete", searchCount: searchCount,
                    chapterCount: chapterCount, contentLength: contentLength, error: nil))
            } catch {
                try Task.checkCancellation()
                let kind: String
                if let error = error as? URLError { kind = "URLError(" + String(error.code.rawValue) + ")" }
                else if case let WebBookError.httpStatus(status, _) = error { kind = "HTTP(" + String(status) + ")" }
                else { kind = String(describing: type(of: error)) }
                reports.append(.init(id: candidate.id, passed: false, stage: stage, searchCount: searchCount,
                    chapterCount: chapterCount, contentLength: contentLength, error: kind))
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(reports).write(to: directory.appendingPathComponent("results.json"), options: .atomic)
        }
        let passed = reports.filter(\.passed).count
        XCTAssertGreaterThanOrEqual(passed, input.requiredPasses, "Live source gate: \(passed)/\(reports.count)")
    }
}

private struct LiveSourceClient: HttpClient {
    private let client = URLSessionHttpClient()
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        var request = request
        request.timeout = min(request.timeout, 20)
        request.callTimeout = min(request.callTimeout, 20)
        return try await client.send(request)
    }
}
