import XCTest
import LegadoCore
@testable import ExploreImagesCheck

@MainActor
final class ExploreImagesCheckTests: XCTestCase {
    func testDuplicateSecondPageStillLoadsThirdPage() async {
        var requested: [Int] = []
        let model = ExploreViewModel { _, page in
            requested.append(page)
            var book = SearchBook(now: 0); book.bookUrl = page < 3 ? "first" : "third"
            return page < 4 ? [book] : []
        }
        await model.select(ExploreKind(title: "分类", url: "/list"))
        await model.loadNextPage()
        XCTAssertTrue(model.hasMore)
        await model.loadNextPage()
        XCTAssertEqual(requested, [1, 2, 3])
        XCTAssertEqual(model.books.compactMap(\.bookUrl), ["first", "third"])
    }

    func testRemoteImageSuccessFailureAndEmptyURL() async {
        let model = RemoteImageViewModel()
        XCTAssertEqual(model.state, .placeholder)
        await model.load(url: "image") {
            XCTAssertEqual(model.state, .loading)
            return Data([1])
        }
        XCTAssertEqual(model.state, .loaded(Data([1])))
        await model.load(url: "broken") { throw URLError(.badServerResponse) }
        XCTAssertEqual(model.state, .failed)
        await model.load(url: nil) { XCTFail("空地址不得下载"); return Data() }
        XCTAssertEqual(model.state, .placeholder)
    }

    func testRemoteImageCancellationDoesNotShowFailure() async {
        let model = RemoteImageViewModel()
        await model.load(url: "image") { throw CancellationError() }
        XCTAssertEqual(model.state, .placeholder)
    }

    func testOlderImageResponseCannotReplaceNewImage() async {
        let model = RemoteImageViewModel()
        var pending: CheckedContinuation<Data, Never>?
        let old = Task {
            await model.load(url: "old") { await withCheckedContinuation { pending = $0 } }
        }
        while pending == nil { await Task.yield() }
        await model.load(url: "new") { Data([2]) }
        pending?.resume(returning: Data([1]))
        await old.value
        XCTAssertEqual(model.state, .loaded(Data([2])))
    }

    func testOnlyEnabledExploreSourcesAreListed() async throws {
        let repository = BookSourceRepository(database: try AppDatabase.inMemory())
        var enabled = BookSourceRow(); enabled.bookSourceUrl = "enabled"; enabled.exploreUrl = "热门::/list"
        var disabled = enabled; disabled.bookSourceUrl = "disabled"; disabled.enabled = false
        var hidden = enabled; hidden.bookSourceUrl = "hidden"; hidden.enabledExplore = false
        try await repository.upsert([enabled, disabled, hidden])
        let model = ExploreSourcesViewModel()
        await model.load(repository: repository)
        XCTAssertEqual(model.sources.map(\.bookSourceUrl), ["enabled"])
    }

    func testExplorePaginationDeduplicatesAndRetriesSamePage() async {
        var requested: [Int] = []
        var fails = true
        let model = ExploreViewModel { _, page in
            requested.append(page)
            if page == 2 && fails { fails = false; throw URLError(.timedOut) }
            var book = SearchBook(now: 0); book.bookUrl = "book"; book.name = "测试"
            return page == 1 ? [book] : []
        }
        await model.select(ExploreKind(title: "分类", url: "/list"))
        XCTAssertEqual(model.books.count, 1)
        await model.loadNextPage()
        XCTAssertNotNil(model.errorMessage)
        await model.loadNextPage()
        XCTAssertEqual(requested, [1, 2, 2])
        XCTAssertFalse(model.hasMore)
        XCTAssertNil(model.errorMessage)
    }
}
