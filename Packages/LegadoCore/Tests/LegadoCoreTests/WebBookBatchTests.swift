import XCTest
@testable import LegadoCore

final class WebBookBatchTests: XCTestCase {
    private func book() -> Book {
        var book = Book(now: 0)
        book.bookUrl = "https://batch.test/book"
        book.tocUrl = "https://batch.test/toc/"
        return book
    }

    private func chapters(sharedURL: Bool = false) -> [BookChapter] {
        (0..<3).map { index in
            var chapter = BookChapter()
            chapter.index = index; chapter.title = "Chapter " + String(index)
            chapter.bookUrl = "https://batch.test/book"
            chapter.url = sharedURL ? "same" : String(index)
            chapter.baseUrl = "https://batch.test/toc/"
            return chapter
        }
    }

    private func source(_ script: String) -> BookSource {
        var source = BookSource()
        source.bookSourceUrl = "https://batch.test"
        source.ruleContent = ContentRule()
        source.ruleContent?.contentBatch = script
        return source
    }

    func testBatchSavesObjectsAndUniqueURLsAndReturnsMissingChapters() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var source = source("java.cacheContent(result[0], ' Old ');java.cacheContent('https://batch.test/toc/1', 'Old');")
        source.ruleContent?.replaceRegex = "##Old##New"
        let web = WebBook(source: source, client: ReplayHttpClient(), configuration: .init(cacheDirectory: directory))
        let missing = try await web.contentBatch(book: book(), chapters: chapters())
        XCTAssertEqual(missing.map(\.index), [2])
        for chapter in chapters().prefix(2) {
            XCTAssertEqual(try BookHelp.content(directory: directory, book: book(), chapter: chapter), "\u{3000}\u{3000}New")
            let cached = try await web.content(book: book(), chapter: chapter)
            XCTAssertEqual(cached.rawContent, "\u{3000}\u{3000}New")
        }
    }

    func testBatchRejectsAmbiguousURLsAndNumbersButAcceptsChapterObjects() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for identifier in ["'same'", "0", "{index:99}"] {
            let web = WebBook(source: source("java.cacheContent(" + identifier + ", 'Body')"), client: ReplayHttpClient(),
                configuration: .init(cacheDirectory: directory))
            do { _ = try await web.contentBatch(book: book(), chapters: chapters(sharedURL: true)); XCTFail("Expected invalid identifier") }
            catch { XCTAssertTrue(String(describing: error).contains("unique batch chapter")) }
        }
        let web = WebBook(source: source("result.forEach(function(c){java.cacheContent(c,'Body '+c.index)})"), client: ReplayHttpClient(),
            configuration: .init(cacheDirectory: directory))
        let missing = try await web.contentBatch(book: book(), chapters: chapters(sharedURL: true))
        XCTAssertTrue(missing.isEmpty)
        for chapter in chapters(sharedURL: true) {
            XCTAssertEqual(try BookHelp.content(directory: directory, book: book(), chapter: chapter), "Body " + String(chapter.index))
        }
    }

    func testBatchAcceptsJSWrappersAndBareJSContainingWrapperText() async throws {
        for script in ["<js>java.cacheContent(result[0], 'First')</js><js>java.cacheContent(result[1], 'Second')</js>",
                       "@js:java.cacheContent(result[0], 'First');java.cacheContent(result[1], 'Second');",
                       "var marker='<js>';java.cacheContent(result[0], 'First');java.cacheContent(result[1], 'Second');"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let web = WebBook(source: source(script), client: ReplayHttpClient(), configuration: .init(cacheDirectory: directory))
            let missing = try await web.contentBatch(book: book(), chapters: chapters())
            XCTAssertEqual(missing.map(\.index), [2])
            XCTAssertEqual(try BookHelp.content(directory: directory, book: book(), chapter: chapters()[0]), "First")
            XCTAssertEqual(try BookHelp.content(directory: directory, book: book(), chapter: chapters()[1]), "Second")
        }
    }

    func testPureJSBatchUsesChaptersThenBookArgumentsAndMissingFunctionFallsBack() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var source = source("")
        source.mainJs = "function getContentBatch(chapters,book){java.cacheContent(chapters[1],book.bookUrl)}"
        var web = WebBook(source: source, client: ReplayHttpClient(), configuration: .init(cacheDirectory: directory))
        let missing = try await web.contentBatch(book: book(), chapters: chapters())
        XCTAssertEqual(missing.map(\.index), [0, 2])
        XCTAssertEqual(try BookHelp.content(directory: directory, book: book(), chapter: chapters()[1]), book().bookUrl)
        source.mainJs = "function getContent(){return 'Body'}"
        web = WebBook(source: source, client: ReplayHttpClient(), configuration: .init(cacheDirectory: directory))
        let fallback = try await web.contentBatch(book: book(), chapters: chapters())
        XCTAssertEqual(fallback.map(\.index), [0, 1, 2])
    }

    func testBatchScopeClosesAndRejectsBlankContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = try WebBookContext(source: source(""), client: ReplayHttpClient(), book: book())
        let batch = try BatchContentContext(chapters: chapters(), context: context, book: book(), directory: directory)
        XCTAssertFalse(try batch.saveContent(identifier: "0", content: " "))
        batch.close()
        XCTAssertFalse(try batch.saveContent(identifier: "0", content: "Body"))
        XCTAssertEqual(batch.missingChapters().count, 3)
        let parser = AnalyzeRule(content: "", engines: [.js: JsEngine()])
        XCTAssertThrowsError(try parser.getString("@js:java.cacheContent('0','Body')"))
    }
}
