import XCTest
@testable import LegadoCore

final class WebBookSearchModelTests: XCTestCase {
    private func book(_ name: String, author: String = "Author", kind: String? = nil, origin: String = "a") -> SearchBook {
        var book = SearchBook(now: 0)
        book.name = name; book.author = author; book.kind = kind; book.origin = origin
        return book
    }

    func testMergeUsesFourRanksUniqueOriginsAndStableOtherOrder() {
        var model = SearchModel()
        let first = [book("Other"), book("Key part"), book("Tags", kind: "Key"), book("Key"), book("Author match", author: "Key")]
        XCTAssertEqual(model.merge(first, key: "Key").map { $0.book.name }, ["Key", "Author match", "Tags", "Key part", "Other"])
        let duplicates = [book("Author match", author: "Key", origin: "b"), book("Other", origin: "b"), book("Other", origin: "b")]
        let results = model.merge(duplicates, key: "Key")
        XCTAssertEqual(results.map { $0.book.name }, ["Author match", "Key", "Tags", "Key part", "Other"])
        XCTAssertEqual(results.first?.book.origin, "a")
        XCTAssertEqual(results.last?.sources.count, 2)
        XCTAssertEqual(model.merge([], key: "Key", precision: true).count, 4)
        XCTAssertEqual(model.merge([book("Next")], key: "Next").count, 1)
    }

    func testSameTitleInDifferentMatchRanksRetainsAndroidBuckets() {
        var model = SearchModel()
        let results = model.merge([book("Key part"), book("Key part", kind: "Key", origin: "b")], key: "Key")
        XCTAssertEqual(results.count, 2)
        XCTAssertNotEqual(results[0].id, results[1].id)
        XCTAssertEqual(results[0].book.origin, "b")
    }

    func testPreciseSearchStopsBeforeInvalidLaterEntryWithoutFetchingDetails() async throws {
        var source = BookSource()
        source.bookSourceUrl = "https://precise.test"
        source.searchUrl = "/search"
        source.ruleSearch = SearchRule()
        source.ruleSearch?.bookList = "tag.a"
        source.ruleSearch?.name = "@js:var n=java.getString('text');if(n==='Invalid')throw 'must stop';n"
        source.ruleSearch?.author = "data-author"
        source.ruleSearch?.bookUrl = "href"
        let url = URL(string: "https://precise.test/search")!
        let client = ReplayHttpClient()
        await client.enqueue(url: url, response: HttpResponse(status: 200,
            body: Data("<a href='/wrong' data-author='Other'>Key</a><a href='/right' data-author='Author'>Key</a><a href='/bad'>Invalid</a>".utf8), finalURL: url))
        let found = try await WebBook(source: source, client: client).preciseSearch(name: "Key", author: "Author")
        XCTAssertEqual(found.bookUrl, "https://precise.test/right")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testChapterRefreshPreservesOnlyMatchingMetadataWhenEnabled() {
        var old = BookChapter()
        old.index = 2; old.title = "Chapter"; old.wordCount = "100"; old.variable = #"{"lyric":"Words"}"#; old.imgUrl = "image"
        var incoming = old
        incoming.url = "new"; incoming.wordCount = "200"; incoming.variable = nil; incoming.imgUrl = nil
        let restored = BookChapterList.upChapterInfo([incoming], previous: [old], enabled: true)[0]
        XCTAssertEqual(restored.url, "new")
        XCTAssertEqual(restored.wordCount, "100")
        XCTAssertEqual(restored.variable, old.variable)
        XCTAssertEqual(restored.imgUrl, "image")
        XCTAssertEqual(BookChapterList.upChapterInfo([incoming], previous: [old], enabled: false)[0], incoming)
        incoming.title = "Different"
        XCTAssertEqual(BookChapterList.upChapterInfo([incoming], previous: [old], enabled: true)[0], incoming)
    }

    func testSimulatedCountMatchesJavaPeriodDayComponentAndLimits() throws {
        var book = Book(now: 0)
        book.totalChapterNum = 100
        book.readConfig = ReadConfig()
        book.readConfig?.readSimulating = true
        book.readConfig?.dailyChapters = 1
        let samples = [(2026, 1, 31, 2026, 2, 28, 29), (2026, 1, 31, 2026, 3, 1, 2),
                       (2026, 1, 1, 2026, 3, 1, 1), (2026, 3, 2, 2026, 3, 1, 0)]
        for (y, m, d, ey, em, ed, expected) in samples {
            book.readConfig?.startDate = try XCTUnwrap(KotlinLocalDate(year: y, month: m, day: d))
            XCTAssertEqual(book.simulatedTotalChapterNum(on: try XCTUnwrap(KotlinLocalDate(year: ey, month: em, day: ed))), expected)
        }
        book.readConfig?.startDate = nil
        book.readConfig?.dailyChapters = 200
        XCTAssertEqual(book.simulatedTotalChapterNum(on: try XCTUnwrap(KotlinLocalDate(year: 2026, month: 9, day: 19))), 100)
        book.readConfig?.readSimulating = false
        XCTAssertEqual(book.simulatedTotalChapterNum(), 100)
    }
}
