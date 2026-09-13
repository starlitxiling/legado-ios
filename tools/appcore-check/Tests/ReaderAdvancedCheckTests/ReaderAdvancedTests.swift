import XCTest
import CoreText
import LegadoCore
@testable import ReaderCheck

final class ReaderAdvancedTests: XCTestCase {
    func testConfigDefaultsAndThemeRoundTrip() throws {
        let defaults = try JSONDecoder().decode(ReadBookConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(defaults.textSize, 20)
        XCTAssertEqual(defaults.titleSize, 0)
        XCTAssertEqual(defaults.pageAnim, 0)
        XCTAssertEqual(defaults.paragraphIndent, "　　")
        var theme = defaults
        theme.titleSize = 10
        theme.textFont = "ExampleFont"
        XCTAssertEqual(try ReadBookConfig.importThemes(ReadBookConfig.exportThemes([theme])), [theme])
    }

    func testNineGridDefaultsAndBoundaries() {
        let expected: [ReaderTapAction] = [.previous, .previous, .next, .previous, .menu, .next, .previous, .next, .next]
        for row in 0..<3 {
            for column in 0..<3 {
                XCTAssertEqual(ReaderTouchMap.action(x: Double(column * 100 + 50), y: Double(row * 100 + 50), width: 300, height: 300), expected[row * 3 + column])
            }
        }
        XCTAssertNil(ReaderTouchMap.action(x: -1, y: 0, width: 300, height: 300))
        XCTAssertNil(ReaderTouchMap.action(x: 300, y: 0, width: 300, height: 300))
    }

    func testAutoReadRateUsesSecondsPerScreen() {
        XCTAssertEqual(AutoReadStep.distance(elapsed: 0.5, speed: 10, height: 800), 40)
        XCTAssertEqual(AutoReadStep.distance(elapsed: 10, speed: 10, height: 800), 800)
        XCTAssertEqual(AutoReadStep.distance(elapsed: -1, speed: 10, height: 800), 0)
        XCTAssertEqual(AutoReadStep.distance(elapsed: 1, speed: 0, height: 800), 0)
    }

    func testTitleFontChangesOccupiedLines() throws {
        var settings = ReaderSettings()
        let title = String(repeating: "章节标题", count: 10)
        let small = try Paginator().paginate(title: title, paragraphs: ["正文"], size: CGSize(width: 250, height: 700), settings: settings)
        settings.titleSize = 20
        let large = try Paginator().paginate(title: title, paragraphs: ["正文"], size: CGSize(width: 250, height: 700), settings: settings)
        func lines(_ pagination: ReaderPagination) -> Int {
            pagination.pages.reduce(0) { $0 + ($1.frame.map { CFArrayGetCount(CTFrameGetLines($0)) } ?? 0) }
        }
        XCTAssertGreaterThan(lines(large), lines(small))
        settings.titleMode = 2
        XCTAssertEqual(try Paginator().paginate(title: title, paragraphs: ["正文"], size: CGSize(width: 250, height: 700), settings: settings).text.string, "正文")
    }

    func testHighlightPersistenceAndTitleOffsets() async throws {
        let repository = BookHighlightRepository(database: try AppDatabase.inMemory())
        var highlight = BookHighlight()
        highlight.time = 100
        highlight.bookUrl = "book"
        highlight.chapterUrl = "chapter"
        highlight.chapterIndex = 3
        highlight.chapterPos = 12
        highlight.chapterPosEnd = 18
        highlight.layoutTitleLength = 10
        highlight.bookText = "示例选区"
        highlight.note = "批注"
        try await repository.upsert(highlight)
        let saved = try await repository.list(bookURL: "book", chapterIndex: 3)
        XCTAssertEqual(saved, [highlight])
        XCTAssertEqual(saved.first?.bodyStart(currentTitleLength: 99), 2)
        XCTAssertEqual(saved.first?.bodyEnd(currentTitleLength: 99), 8)
        let other = try await repository.list(bookURL: "other", chapterIndex: 3)
        XCTAssertTrue(other.isEmpty)
    }

    func testCachePresenceRules() {
        XCTAssertTrue(ReaderCacheStatus.hasContent(isLocalTXT: true, isVolume: false, chapterURL: "x", title: "t", cached: false))
        XCTAssertTrue(ReaderCacheStatus.hasContent(isLocalTXT: false, isVolume: true, chapterURL: "卷一-1", title: "卷一", cached: false))
        XCTAssertFalse(ReaderCacheStatus.hasContent(isLocalTXT: false, isVolume: false, chapterURL: "x", title: "t", cached: false))
        XCTAssertTrue(ReaderCacheStatus.hasContent(isLocalTXT: false, isVolume: false, chapterURL: "x", title: "t", cached: true))
    }

    func testCacheRequiresDecodablePayloadAndIncludesSourceIdentity() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/b9-cache-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var book = Book(); book.bookUrl = "https://book"; book.origin = "source"
        var chapter = BookChapter(); chapter.url = "https://chapter"; chapter.title = "章节"
        let file = try ReaderCacheStatus.fileURL(book: book, chapter: chapter, directory: directory)
        XCTAssertFalse(ReaderCacheStatus.hasContent(book: book, chapter: chapter, directory: directory))
        try Data("invalid".utf8).write(to: file)
        XCTAssertFalse(ReaderCacheStatus.hasContent(book: book, chapter: chapter, directory: directory))
        try Data(#"{"rawContent":"正文"}"#.utf8).write(to: file)
        XCTAssertTrue(ReaderCacheStatus.hasContent(book: book, chapter: chapter, directory: directory))
        book.origin = "different"
        XCTAssertFalse(ReaderCacheStatus.hasContent(book: book, chapter: chapter, directory: directory))
    }

    func testTitleSpacingMovesFirstBaseline() throws {
        var settings = ReaderSettings()
        func firstY(_ settings: ReaderSettings) throws -> CGFloat {
            let value = try Paginator().paginate(title: "章节", paragraphs: ["正文"], size: CGSize(width: 250, height: 700), settings: settings)
            let frame = try XCTUnwrap(value.pages.first?.frame)
            var origin = CGPoint.zero
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 1), &origin)
            return origin.y
        }
        let original = try firstY(settings)
        settings.titleTopSpacing = 30
        XCTAssertEqual(original - (try firstY(settings)), 30, accuracy: 0.1)
    }
}
