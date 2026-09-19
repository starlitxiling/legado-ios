import XCTest
import UIKit
@testable import Legado

@MainActor
final class AppLaunchTests: XCTestCase {
    func testRegistersDuringLaunchBeforeOpeningDatabase() throws {
        var events: [String] = []
        let delegate = LegadoAppDelegate(makeContainer: {
            events.append("database")
            return try AppContainer.inMemory()
        }, registerBackgroundTask: { _ in
            events.append("register")
            return false
        })

        XCTAssertTrue(delegate.application(.shared, didFinishLaunchingWithOptions: nil))
        XCTAssertEqual(events, ["register"])
        XCTAssertNil(delegate.container)
        delegate.openDatabase()
        XCTAssertEqual(events, ["register", "database"])
        XCTAssertNotNil(delegate.container)
        XCTAssertNil(delegate.startupError)
    }

    func testDatabaseRetryDoesNotRegisterAgain() throws {
        var registrations = 0
        var attempts = 0
        let delegate = LegadoAppDelegate(makeContainer: {
            attempts += 1
            if attempts == 1 {
                throw NSError(domain: "AppLaunchTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Database temporarily unavailable"])
            }
            return try AppContainer.inMemory()
        }, registerBackgroundTask: { _ in
            registrations += 1
            return false
        })

        XCTAssertTrue(delegate.application(.shared, didFinishLaunchingWithOptions: nil))
        delegate.openDatabase()
        XCTAssertNil(delegate.container)
        XCTAssertEqual(delegate.startupError, "Database temporarily unavailable")
        delegate.openDatabase()
        XCTAssertNotNil(delegate.container)
        XCTAssertNil(delegate.startupError)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(registrations, 1)
    }

    func testRepeatedStartupKeepsExistingContainerAndRegistration() throws {
        var registrations = 0
        var opens = 0
        let delegate = LegadoAppDelegate(makeContainer: {
            opens += 1
            return try AppContainer.inMemory()
        }, registerBackgroundTask: { _ in
            registrations += 1
            return false
        })

        XCTAssertTrue(delegate.application(.shared, didFinishLaunchingWithOptions: nil))
        delegate.openDatabase()
        let original = try XCTUnwrap(delegate.container)
        XCTAssertTrue(delegate.application(.shared, didFinishLaunchingWithOptions: nil))
        delegate.openDatabase()
        XCTAssertTrue(delegate.container === original)
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(registrations, 1)
    }
}
