import Foundation
import XCTest
@testable import DatabaseLifecycleCheck

final class DatabaseLifecycleCoordinatorTests: XCTestCase {
    func testBackgroundWaitsForAllWritesAndForegroundCancelsPendingSuspension() {
        let center = NotificationCenter()
        var suspended = 0
        let coordinator = DatabaseLifecycleCoordinator(notificationCenter: center, suspend: { suspended += 1 }, resume: {})
        let background = Notification.Name("test.background"), foreground = Notification.Name("test.foreground")
        coordinator.observe(background: background, foreground: foreground)
        let first = coordinator.beginProgressWrite(), second = coordinator.beginProgressWrite()
        center.post(name: background, object: nil)
        XCTAssertEqual(suspended, 0)
        first(); first()
        XCTAssertEqual(suspended, 0)
        second()
        XCTAssertEqual(suspended, 1)
        center.post(name: foreground, object: nil)
        let finish = coordinator.beginProgressWrite()
        center.post(name: background, object: nil)
        center.post(name: foreground, object: nil)
        finish()
        XCTAssertEqual(suspended, 1)
        XCTAssertFalse(coordinator.isSuspended)
    }

    func testResumesSynchronouslyBeforeRefreshAndDeduplicatesTransitions() {
        let center = NotificationCenter()
        let background = Notification.Name("test.background")
        let foreground = Notification.Name("test.foreground")
        var events: [String] = []
        let coordinator = DatabaseLifecycleCoordinator(notificationCenter: center,
                                                       suspend: { events.append("suspend") },
                                                       resume: { events.append("resume") })
        coordinator.observe(background: background, foreground: foreground)
        let token = center.addObserver(forName: DatabaseLifecycleCoordinator.readyToRefreshNotification,
                                       object: coordinator, queue: nil) { _ in events.append("refresh") }
        defer { center.removeObserver(token) }

        center.post(name: foreground, object: nil)
        XCTAssertEqual(events, [])
        center.post(name: background, object: nil)
        center.post(name: background, object: nil)
        XCTAssertTrue(coordinator.isSuspended)
        XCTAssertEqual(events, ["suspend"])
        center.post(name: foreground, object: nil)
        XCTAssertFalse(coordinator.isSuspended)
        XCTAssertEqual(events, ["suspend", "resume", "refresh"])
        center.post(name: foreground, object: nil)
        XCTAssertEqual(events, ["suspend", "resume", "refresh"])
        center.post(name: background, object: nil)
        center.post(name: foreground, object: nil)
        XCTAssertEqual(events, ["suspend", "resume", "refresh", "suspend", "resume", "refresh"])
    }

    func testRepeatedObservationAndDeallocationDoNotLeaveObservers() {
        let center = NotificationCenter()
        let background = Notification.Name("test.background")
        let foreground = Notification.Name("test.foreground")
        var suspensions = 0
        var coordinator: DatabaseLifecycleCoordinator? = DatabaseLifecycleCoordinator(
            notificationCenter: center, suspend: { suspensions += 1 }, resume: {})
        coordinator?.observe(background: background, foreground: foreground)
        coordinator?.observe(background: background, foreground: foreground)
        center.post(name: background, object: nil)
        XCTAssertEqual(suspensions, 1)
        weak var released = coordinator
        coordinator = nil
        XCTAssertNil(released)
        center.post(name: foreground, object: nil)
        center.post(name: background, object: nil)
        XCTAssertEqual(suspensions, 1)
    }
}
