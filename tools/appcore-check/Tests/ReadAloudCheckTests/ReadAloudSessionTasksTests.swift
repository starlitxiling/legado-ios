import XCTest
@testable import ReadAloudCheck

@MainActor
final class ReadAloudSessionTasksTests: XCTestCase {
    func test8StopCancelsEveryTaskAndSerializesNextRoundAfterCleanup() async {
        let owner = ReadAloudSessionTasks()
        var started = 0, cancelled = 0, cleaned = false, ranAfterCleanup = false
        for _ in 0..<3 {
            owner.start {
                started += 1
                do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                catch { cancelled += 1 }
            }
        }
        while started != 3 { await Task.yield() }
        owner.cancelAll { cleaned = true }
        owner.start { ranAfterCleanup = cleaned }
        await owner.waitUntilIdle()
        XCTAssertEqual(cancelled, 3)
        XCTAssertTrue(ranAfterCleanup)
        XCTAssertEqual(owner.count, 0)
    }
}
