import XCTest
import UIKit
@testable import Legado

@MainActor
final class ReaderProgressBackgroundTaskTests: XCTestCase {
    func testExpirationEndsSynchronouslyAndOnlyOnce() {
        var expiration: (@Sendable () -> Void)?
        var begins = 0
        var ended: [UIBackgroundTaskIdentifier] = []
        let identifier = UIBackgroundTaskIdentifier(rawValue: 42)
        let task = ReaderProgressBackgroundTask(begin: {
            begins += 1; expiration = $0; return identifier
        }, end: { ended.append($0) })
        expiration?()
        XCTAssertEqual(ended, [identifier])
        task.end()
        expiration?()
        task.end()
        XCTAssertEqual(begins, 1)
        XCTAssertEqual(ended, [identifier])
    }

    func testNormalCompletionBeforeExpirationEndsOnlyOnce() {
        var expiration: (@Sendable () -> Void)?
        var ended: [UIBackgroundTaskIdentifier] = []
        let identifier = UIBackgroundTaskIdentifier(rawValue: 43)
        let task = ReaderProgressBackgroundTask(begin: { expiration = $0; return identifier }, end: { ended.append($0) })
        task.end()
        expiration?()
        task.end()
        XCTAssertEqual(ended, [identifier])
    }

    func testInvalidBackgroundTaskNeedsNoEnd() {
        let task = ReaderProgressBackgroundTask(begin: { _ in .invalid }, end: { _ in XCTFail("Invalid task must not end") })
        task.end()
    }
}
