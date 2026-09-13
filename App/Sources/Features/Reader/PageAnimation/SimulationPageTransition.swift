import SwiftUI
import UIKit

struct SimulationPageTransition<Content: View>: UIViewControllerRepresentable {
    let page: Int
    let content: Content

    init(page: Int, @ViewBuilder content: () -> Content) { self.page = page; self.content = content() }

    func makeCoordinator() -> Coordinator { Coordinator(page: page) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
        controller.setViewControllers([UIHostingController(rootView: content)], direction: .forward, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.update(controller, page: page, content: content)
    }

    final class Coordinator {
        var page: Int
        private var isAnimating = false
        private var pending: (Int, Content)?
        init(page: Int) { self.page = page }

        func update(_ controller: UIPageViewController, page: Int, content: Content) {
            if isAnimating { pending = (page, content); return }
            guard self.page != page else {
                (controller.viewControllers?.first as? UIHostingController<Content>)?.rootView = content
                return
            }
            let direction: UIPageViewController.NavigationDirection = page >= self.page ? .forward : .reverse
            self.page = page; isAnimating = true
            controller.setViewControllers([UIHostingController(rootView: content)], direction: direction, animated: true) { [weak self, weak controller] _ in
                guard let self, let controller else { return }
                self.isAnimating = false
                if let pending = self.pending {
                    self.pending = nil
                    self.update(controller, page: pending.0, content: pending.1)
                }
            }
        }
    }
}
