import XCTest
@testable import LegadoCore

final class ImageRetentionTests: XCTestCase {
    func testRetentionKeepsChapterWindowAcrossDownloaderInstances() async throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/tmp/retention-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient()
        let loader = ImageDownloader(client: client, cacheDirectory: directory)
        var book = Book(now: 0); book.bookUrl = "https://example.invalid/book"; book.name = "漫画"; book.type = 2
        let urls = (0..<7).map { "https://example.invalid/\($0).jpg" }
        for (index, address) in urls.enumerated() {
            let url = URL(string: address)!
            await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data([UInt8(index + 1)]), finalURL: url))
            _ = try await loader.load(url: address, book: book, isCover: false)
            try await loader.recordChapterImages(book: book, chapterIndex: index, urls: [address])
        }
        let reopened = ImageDownloader(client: client, cacheDirectory: directory)
        try await reopened.pruneChapterImages(book: book, chapterIndex: 3, retainPrevious: 0, preDownload: 1)
        XCTAssertEqual(try imageCount(directory), 7, "零表示不清理")
        try await reopened.pruneChapterImages(book: book, chapterIndex: 3, retainPrevious: 1, preDownload: 2)
        XCTAssertEqual(try imageCount(directory), 4, "保留闭区间 2...5")
        for index in 2...5 {
            let data = try await reopened.load(url: urls[index], book: book, isCover: false)
            XCTAssertEqual(data, Data([UInt8(index + 1)]))
        }
        let requests = await client.requests
        XCTAssertEqual(requests.count, 7, "保留的文件不重复下载")
    }

    func testRetentionDoesNotDeleteOtherBooksOrCovers() async throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/tmp/retention-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = ImageDownloader(client: ReplayHttpClient(), cacheDirectory: directory)
        var first = Book(now: 0); first.bookUrl = "first"; first.name = "同名"
        var second = first; second.bookUrl = "second"
        let url = "data:image/jpeg;base64,AQ=="
        _ = try await loader.load(url: url, book: first, isCover: false)
        _ = try await loader.load(url: url, book: second, isCover: false)
        _ = try await loader.load(url: url, book: first, isCover: true)
        try await loader.recordChapterImages(book: first, chapterIndex: 0, urls: [url])
        try await loader.pruneChapterImages(book: first, chapterIndex: 5, retainPrevious: 1, preDownload: 0)
        XCTAssertEqual(try imageCount(directory), 2)
    }

    private func imageCount(_ directory: URL) throws -> Int {
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)!
        return files.compactMap { $0 as? URL }.filter { $0.pathExtension == "jpg" }.count
    }

    func testUnindexedLegacyCacheIsPreservedUntilChapterMetadataExists() async throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/tmp/retention-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = ImageDownloader(client: ReplayHttpClient(), cacheDirectory: directory)
        var book = Book(now: 0); book.bookUrl = "legacy"; book.name = "旧缓存"
        _ = try await loader.load(url: "data:image/jpeg;base64,AQ==", book: book, isCover: false)
        try await loader.pruneChapterImages(book: book, chapterIndex: 20, retainPrevious: 2, preDownload: 0)
        XCTAssertEqual(try imageCount(directory), 1)
        let current = "data:image/jpeg;base64,Ag=="
        _ = try await loader.load(url: current, book: book, isCover: false)
        try await loader.recordChapterImages(book: book, chapterIndex: 20, urls: [current])
        try await loader.pruneChapterImages(book: book, chapterIndex: 20, retainPrevious: 2, preDownload: 0)
        XCTAssertEqual(try imageCount(directory), 2, "建立当前章节索引不能误删尚未索引的旧缓存")
    }
}
