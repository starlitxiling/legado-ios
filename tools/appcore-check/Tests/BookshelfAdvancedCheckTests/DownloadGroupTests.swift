import XCTest
import LegadoCore
@testable import BookshelfAdvancedCheck

@MainActor
final class DownloadGroupTests: XCTestCase {
    func testGroupsCountStatesAndLimitVisibleRows() async {
        let cache = CacheBook(maximumConcurrent: 1, retryLimit: 0, failurePauseThreshold: 0)
        await cache.enqueue(bookURL: "big", chapters: Array(0..<200)) { index in
            if index < 5 { throw URLError(.timedOut) }
            if index < 10 { return }
            try await Task.sleep(for: .seconds(30))
        }
        try? await Task.sleep(for: .milliseconds(300))
        await cache.pause(bookURL: "big")
        await cache.waitUntilIdle()
        let groups = DownloadCenterModel.BookGroup.make(await cache.snapshot())
        XCTAssertEqual(groups.count, 1)
        let group = groups[0]
        XCTAssertEqual(group.total, 200)
        XCTAssertEqual(group.failed, 5)
        XCTAssertEqual(group.completed, 5)
        XCTAssertEqual(group.paused, 190)
        XCTAssertEqual(group.visible.count, 5 + DownloadCenterModel.BookGroup.visibleQueuedLimit)
        XCTAssertEqual(Array(group.visible.prefix(5)).map(\.state), Array(repeating: .failed, count: 5))
        XCTAssertEqual(group.hidden, 200 - 5 - group.visible.count)
        let again = DownloadCenterModel.BookGroup.make(await cache.snapshot())
        XCTAssertEqual(groups, again)
    }
}
