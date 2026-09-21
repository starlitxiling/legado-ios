import XCTest
@testable import LegadoCore

final class BookArchiveTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testRARAndSevenZipEntryReadingAndLimits() throws {
        let fixtures = root.appendingPathComponent("tools/archive-probe/Tests/ArchiveProbeTests/Fixtures")
        for name in ["rar5.rar", "lzma.7z", "lzma2-solid.7z"] {
            let url = fixtures.appendingPathComponent(name)
            let archive = try BookArchive(url: url)
            XCTAssertEqual(try archive.read("chapter.txt"), Data(String(repeating: "Synthetic archive probe chapter.\n", count: 100).utf8))
            if name == "lzma2-solid.7z" {
                XCTAssertEqual(archive.entries.count, 2)
                XCTAssertEqual(try archive.read("second.txt"), Data("Second synthetic chapter.\n".utf8))
            }
            XCTAssertThrowsError(try BookArchive(url: url, maximumExpandedSize: 100))
            XCTAssertThrowsError(try archive.read("absent.txt"))
            let memory = try BookArchive(data: Data(contentsOf: url), format: url.pathExtension)
            XCTAssertEqual(try memory.read("chapter.txt"), try archive.read("chapter.txt"))
        }
    }

    func testZipImportsAllBooksInNestedDirectories() throws {
        let archive = try BookArchive(url: root.appendingPathComponent("Tests/Fixtures/localbook/two-books.zip"))
        XCTAssertEqual(archive.entries.map(\.name), ["First.txt", "nested/Second.txt", "notes.json"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try archive.extractBooks(to: directory)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["First.txt", "Second.txt"])
        for url in urls {
            let parsed = try LocalBook.parse(url: url)
            let last = try XCTUnwrap(parsed.chapters.last)
            XCTAssertTrue(try LocalBook.content(book: parsed.book, chapter: last).contains("final page"))
        }
        XCTAssertThrowsError(try archive.extractBooks(to: directory))
    }

    func testRejectsUnsafePathsDuplicateNamesAndSymbolicLinks() throws {
        for name in ["traversal.zip", "duplicate.zip", "symlink.zip"] {
            XCTAssertThrowsError(try BookArchive(url: root.appendingPathComponent("Tests/Fixtures/localbook/" + name)), name)
        }
    }

    func testRejectsPreCancelledExtraction() async throws {
        let url = root.appendingPathComponent("Tests/Fixtures/localbook/two-books.zip")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try BookArchive(url: url).read("First.txt")
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }
}
