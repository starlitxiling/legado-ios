import XCTest
import LegadoCore
@testable import ReaderCheck

@MainActor
final class ReaderSourceRecoveryTests: XCTestCase {
    func testFailedContentSwitchesOnlyAfterReplacementChapterLoads() async throws {
        let database = try AppDatabase.inMemory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var row = BookRow(); row.bookUrl = "https://old.test/book"; row.origin = "https://old.test"
        row.name = "Recovery"; row.author = "Author"; row.group = 4
        try await BookshelfRepository(database: database).insert(row)
        var chapter = BookChapterRow(); chapter.bookUrl = row.bookUrl; chapter.url = "https://old.test/chapter"; chapter.title = "Chapter"
        try await ChapterRepository(database: database).replaceAll(bookUrl: row.bookUrl, chapters: [chapter])
        var source = BookSourceRow(); source.bookSourceUrl = "https://new.test"; source.bookSourceName = "Replacement"
        source.mainJs = """
        function search(key) { return [{name:key,author:'Author',bookUrl:baseUrl+'/book'}]; }
        function getBookInfo() { return {tocUrl:baseUrl+'/toc'}; }
        function getChapters() { return [{title:'Chapter',url:baseUrl+'/chapter'}]; }
        function getContent() { return 'Recovered body'; }
        """
        try await BookSourceRepository(database: database).upsert([source])
        let model = ReaderViewModel(database: database, client: ReplayHttpClient(), cacheDirectory: root, preDownloadCount: { 0 })
        model.autoChangeSource = { false }
        await model.load(bookURL: row.bookUrl)
        XCTAssertEqual(model.book?.bookUrl, row.bookUrl)
        XCTAssertNotNil(model.errorMessage)
        model.autoChangeSource = { true }
        await model.retry()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.book?.origin, "https://new.test")
        XCTAssertEqual(model.book?.group, 4)
        XCTAssertTrue(model.pagination?.text.string.contains("Recovered body") == true)
        let old = try await BookshelfRepository(database: database).get(bookUrl: row.bookUrl)
        XCTAssertNil(old)
        await model.close()
    }

    func testUnusableCandidatesLeaveOriginalBookIntact() async throws {
        let database = try AppDatabase.inMemory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var row = BookRow(); row.bookUrl = "https://old.test/book"; row.origin = "https://old.test"; row.name = "Recovery"
        try await BookshelfRepository(database: database).insert(row)
        var source = BookSourceRow(); source.bookSourceUrl = "https://empty.test"
        source.mainJs = """
        function search(key) { return [{name:key,author:'',bookUrl:baseUrl+'/book'}]; }
        function getBookInfo() { return {tocUrl:baseUrl+'/toc'}; }
        function getChapters() { return [{title:'Chapter',url:baseUrl+'/chapter'}]; }
        function getContent() { throw 'Unavailable content'; }
        """
        try await BookSourceRepository(database: database).upsert([source])
        let model = ReaderViewModel(database: database, client: ReplayHttpClient(), cacheDirectory: root, preDownloadCount: { 0 })
        model.autoChangeSource = { true }
        await model.load(bookURL: row.bookUrl)
        XCTAssertNotNil(model.errorMessage)
        let saved = try await BookshelfRepository(database: database).get(bookUrl: row.bookUrl)
        XCTAssertNotNil(saved)
        XCTAssertNil(model.pagination)
        await model.close()
    }
}
