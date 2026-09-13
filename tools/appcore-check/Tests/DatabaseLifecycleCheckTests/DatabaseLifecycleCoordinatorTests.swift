import Foundation
import XCTest
@testable import DatabaseLifecycleCheck

final class DatabaseLifecycleCoordinatorTests: XCTestCase {
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
