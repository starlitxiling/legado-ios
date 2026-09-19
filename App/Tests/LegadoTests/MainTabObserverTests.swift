import XCTest
import UIKit
@testable import Legado

@MainActor
final class MainTabObserverTests: XCTestCase {
    func testReselectionPreservesDelegateAndTracksVisiblePages() {
        let controller = UITabBarController()
        let shelf = UIViewController(), my = UIViewController()
        controller.viewControllers = [shelf, my]
        controller.selectedViewController = shelf
        let original = SelectionDelegate()
        controller.delegate = original
        let probe = MainTabObserver.Probe()
        probe.pages = [("bookshelf", "Shelf"), ("my", "My")]
        shelf.addChild(probe)
        probe.didMove(toParent: shelf)
        probe.install()
        XCTAssertTrue(controller.delegate === probe)
        XCTAssertEqual(controller.tabBar.items?.map(\.accessibilityIdentifier), ["main.tab.bookshelf", "main.tab.my"])
        let reselected = expectation(forNotification: MainTabObserver.reselectedNotification, object: nil) {
            $0.object as? String == "bookshelf"
        }
        XCTAssertTrue(probe.tabBarController(controller, shouldSelect: shelf))
        probe.tabBarController(controller, didSelect: shelf)
        wait(for: [reselected], timeout: 1)
        XCTAssertEqual(original.selections, 1)
        XCTAssertTrue(probe.tabBarController(controller, shouldSelect: my))
        controller.selectedViewController = my
        probe.tabBarController(controller, didSelect: my)
        XCTAssertEqual(original.selections, 2)
        probe.detach()
        XCTAssertTrue(controller.delegate === original)
    }
}

private final class SelectionDelegate: NSObject, UITabBarControllerDelegate {
    var selections = 0
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) { selections += 1 }
}
