import XCTest
@testable import LegadoCore

final class CacheBookAutoPauseTests: XCTestCase {
    func testConsecutiveFailuresPauseRemainingChaptersWithReason() async {
        let cache = CacheBook(maximumConcurrent: 2, retryLimit: 0, failurePauseThreshold: 10)
        await cache.enqueue(bookURL: "book", chapters: Array(0..<30)) { _ in throw URLError(.networkConnectionLost) }
        await cache.waitUntilIdle()
        let states = await cache.snapshot().map(\.state)
        let failed = states.filter { $0 == .failed }.count
        XCTAssertGreaterThanOrEqual(failed, 10)
        XCTAssertLessThan(failed, 30)
        XCTAssertEqual(states.filter { $0 == .paused }.count, 30 - failed)
        let reason = await cache.pauseReason(bookURL: "book")
        XCTAssertTrue(reason?.hasPrefix("连续 10 章下载失败，已自动暂停") == true, reason ?? "nil")
        await cache.resume(bookURL: "book")
        let cleared = await cache.pauseReason(bookURL: "book")
        XCTAssertNil(cleared)
        await cache.cancel(bookURL: "book")
    }

    func testSuccessResetsFailureStreakAndOtherBooksContinue() async {
        let cache = CacheBook(maximumConcurrent: 1, retryLimit: 0, failurePauseThreshold: 3)
        await cache.enqueue(bookURL: "mixed", chapters: Array(0..<12)) { index in
            if index % 3 == 2 { return }
            throw URLError(.timedOut)
        }
        await cache.enqueue(bookURL: "dead", chapters: Array(0..<5)) { _ in throw URLError(.cannotConnectToHost) }
        await cache.waitUntilIdle()
        let mixed = await cache.snapshot().filter { $0.bookURL == "mixed" }.map(\.state)
        XCTAssertFalse(mixed.contains(.paused))
        XCTAssertEqual(mixed.filter { $0 == .completed }.count, 4)
        let mixedReason = await cache.pauseReason(bookURL: "mixed")
        XCTAssertNil(mixedReason)
        let dead = await cache.snapshot().filter { $0.bookURL == "dead" }.map(\.state)
        XCTAssertEqual(dead.filter { $0 == .failed }.count, 3)
        XCTAssertEqual(dead.filter { $0 == .paused }.count, 2)
    }
}
