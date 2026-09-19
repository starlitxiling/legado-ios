import SwiftUI
import UIKit

struct MainTabObserver: UIViewControllerRepresentable {
    static let reselectedNotification = Notification.Name("LegadoMainTabReselected")
    let pages: [(id: String, title: String)]
    @Environment(\.themeColors) private var colors

    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.pages = pages
        probe.unselectedColor = UIColor(colors.textSecondary)
        probe.selectedColor = UIColor(colors.accent)
        probe.install()
    }

    static func dismantleUIViewController(_ probe: Probe, coordinator: ()) { probe.detach() }

    final class Probe: UIViewController, UITabBarControllerDelegate {
        var pages: [(id: String, title: String)] = []
        var unselectedColor = UIColor.secondaryLabel
        var selectedColor = UIColor.tintColor
        private weak var observed: UITabBarController?
        private weak var previous: (any UITabBarControllerDelegate)?
        private weak var reselected: UIViewController?

        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil { install() }
        }

        func install() {
            guard let controller = tabBarController else { return }
            if controller.delegate !== self {
                if let probe = controller.delegate as? Probe { previous = probe.previous }
                else { previous = controller.delegate }
                observed = controller
                controller.delegate = self
            }
            controller.tabBar.unselectedItemTintColor = unselectedColor
            controller.tabBar.tintColor = selectedColor
            let appearance = controller.tabBar.standardAppearance.copy()
            for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
                layout.normal.iconColor = unselectedColor
                layout.selected.iconColor = selectedColor
            }
            controller.tabBar.standardAppearance = appearance
            controller.tabBar.scrollEdgeAppearance = appearance
            for (index, item) in (controller.tabBar.items ?? []).enumerated() where pages.indices.contains(index) {
                item.accessibilityLabel = pages[index].title
                item.accessibilityIdentifier = "main.tab." + pages[index].id
            }
        }

        func detach() {
            if let observed, observed.delegate === self { observed.delegate = previous }
            observed = nil
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            let allowed = previous?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
            reselected = allowed && tabBarController.selectedViewController === viewController ? viewController : nil
            return allowed
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            previous?.tabBarController?(tabBarController, didSelect: viewController)
            guard reselected === viewController,
                  let index = tabBarController.viewControllers?.firstIndex(where: { $0 === viewController }),
                  pages.indices.contains(index) else { reselected = nil; return }
            reselected = nil
            NotificationCenter.default.post(name: MainTabObserver.reselectedNotification, object: pages[index].id)
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (previous?.responds(to: selector) ?? false)
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            if previous?.responds(to: selector) == true { return previous }
            return super.forwardingTarget(for: selector)
        }
    }
}
