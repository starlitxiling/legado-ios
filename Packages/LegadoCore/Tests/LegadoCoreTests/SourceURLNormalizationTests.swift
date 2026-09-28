import XCTest
@testable import LegadoCore

final class SourceURLNormalizationTests: XCTestCase {
    func testRealBackupNormalizationOffline() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("App/Sources").path) {
            let parent = root.deletingLastPathComponent()
            guard parent != root else { throw XCTSkip("Repository root unavailable") }
            root = parent
        }
        let fixture = root.appendingPathComponent(".build/fixtures-local/real-backup.zip")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Local private backup unavailable") }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let archive = try BackupArchive(data: Data(contentsOf: fixture))
        let booksData = try XCTUnwrap(archive.entries["bookshelf.json"])
        let sourceData = try XCTUnwrap(archive.entries["bookSource.json"])
        let books = try JSONDecoder().decode([Book].self, from: booksData)
        let sources = try JSONDecoder().decode([BookSource].self, from: sourceData)
        let urls = sources.compactMap(\.bookSourceUrl)
        let exact = Set(urls)
        let missing = books.filter { !LocalBook.isLocal($0) && !exact.contains($0.origin ?? "") }
        let matched = missing.filter { BookSourceURL.match($0.origin ?? "", candidates: urls) != nil }
        let ambiguous = missing.filter { book in
            urls.filter { BookSourceURL.normalized($0) == BookSourceURL.normalized(book.origin ?? "") }.count > 1
        }
        let result = "ambiguous=\(ambiguous.count), sources=\(urls.count), missing=\(missing.count), reconnected=\(matched.count), remaining=\(missing.count - matched.count)"
        try Data(result.utf8).write(to: temporary.appendingPathComponent("normalization-result.txt"))
        print(result)
        XCTAssertEqual(urls.count, 4198)
        XCTAssertEqual(missing.count, 24)
        XCTAssertEqual(matched.count, 13)
        XCTAssertEqual(ambiguous.count, 7)
    }
}
