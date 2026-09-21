import XCTest
import LegadoCore
@testable import ExploreImagesCheck

@MainActor
final class ExploreImagesCheckTests: XCTestCase {
    func testAccordionGroupFilterControlsAndSourceOrdering() async throws {
        let db = try AppDatabase.inMemory()
        let repository = BookSourceRepository(database: db), states = SourceStateRepository(database: db)
        let client = ReplayHttpClient()
        var first = BookSourceRow(); first.bookSourceUrl = "https://first.test"; first.bookSourceName = "First"
        first.bookSourceGroup = "A, B"; first.exploreUrl = #"[{"title":"Sort","type":"select","chars":["New","Hot"],"default":"Hot","action":"infoMap.save();java.reUiView()"},{"title":"Books","url":"/books"}]"#
        var second = first; second.bookSourceUrl = "https://second.test"; second.bookSourceName = "Second"
        second.bookSourceGroup = "B"; second.exploreUrl = "Other::/other"
        try await repository.upsert([first, second])
        let model = ExploreSourcesViewModel()
        await model.load(repository: repository)
        XCTAssertEqual(model.groups, ["A", "B"])
        model.selectedGroup = "A"
        XCTAssertEqual(model.filteredSources.count, 1)
        let source = try XCTUnwrap(model.sources.first)
        await model.toggle(source, client: client, stateRepository: states)
        XCTAssertEqual(model.expandedURL, source.bookSourceUrl)
        XCTAssertEqual(model.controlValues["Sort"], "Hot")
        model.controlValues["Sort"] = "New"
        await model.act(try XCTUnwrap(model.kinds.first), source: source, client: client, stateRepository: states)
        XCTAssertEqual(model.controlValues["Sort"], "New")
        let other = model.sources[1]
        await model.toggle(other, client: client, stateRepository: states)
        XCTAssertEqual(model.kinds.map(\.title), ["Other"])
        await model.toggle(other, client: client, stateRepository: states)
        XCTAssertNil(model.expandedURL)
        XCTAssertTrue(model.kinds.isEmpty)
        await model.toggle(source, client: client, stateRepository: states)
        model.controlValues["Sort"] = "Unsaved"
        await model.toggle(other, client: client, stateRepository: states)
        await model.toggle(source, client: client, stateRepository: states)
        XCTAssertEqual(model.controlValues["Sort"], "Unsaved")
        await model.moveToTop(other, repository: repository)
        XCTAssertEqual(model.sources.first?.bookSourceUrl, other.bookSourceUrl)
        await model.delete(other, repository: repository)
        XCTAssertEqual(model.sources.count, 1)
    }

    func testLateCategoriesCannotReplaceNewlyExpandedSource() async throws {
        let states = SourceStateRepository(database: try AppDatabase.inMemory())
        let client = DelayedExploreClient()
        var first = BookSource(); first.bookSourceUrl = "https://first.test"
        first.exploreUrl = "@js:java.ajax('https://first.test/categories')"
        var second = BookSource(); second.bookSourceUrl = "https://second.test"; second.exploreUrl = "New::/new"
        let model = ExploreSourcesViewModel()
        let task = Task { await model.toggle(first, client: client, stateRepository: states) }
        await client.waitForStart()
        await model.toggle(second, client: client, stateRepository: states)
        await client.release()
        await task.value
        XCTAssertEqual(model.expandedURL, second.bookSourceUrl)
        XCTAssertEqual(model.kinds.map(\.title), ["New"])
        XCTAssertFalse(model.kindsLoading)
    }

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

private actor DelayedExploreClient: HttpClient {
    private var continuation: CheckedContinuation<Void, Never>?
    private var ready: CheckedContinuation<Void, Never>?
    func waitForStart() async {
        if continuation != nil { return }
        await withCheckedContinuation { ready = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        await withCheckedContinuation { continuation = $0; ready?.resume(); ready = nil }
        return HttpResponse(status: 200, body: Data("Old::/old".utf8), finalURL: request.url)
    }
}
