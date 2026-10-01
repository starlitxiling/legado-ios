import SwiftUI
import UIKit

struct SimulationPageTransition<Content: View, Next: View, Previous: View>: UIViewControllerRepresentable {
    var paperColor: Color = ReaderPaperColor.resolve(settings: ReaderSettings()).color
    let page: Int
    let enabled: Bool
    let canPrevious: Bool
    let canNext: Bool
    let turn: (Bool) async -> Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let next: () -> Next
    @ViewBuilder let previous: () -> Previous

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
        controller.isDoubleSided = true
        controller.delegate = context.coordinator
        context.coordinator.install(controller, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.update(self, controller: controller)
    }

    static func dismantleUIViewController(_ controller: UIPageViewController, coordinator: Coordinator) {
        coordinator.task?.cancel()
        controller.dataSource = nil; controller.delegate = nil
    }

    final class Face: UIHostingController<AnyView> {
        let index: Int
        init(index: Int, rootView: AnyView) { self.index = index; super.init(rootView: rootView); view.backgroundColor = .clear }
        @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var value: SimulationPageTransition
        var task: Task<Void, Never>?
        private var pending: SimulationPageTransition?
        private var faces: [Int: Face] = [:]
        private var interacting = false
        private var animating = false
        private var committing = false
        /// The curl already played for a finger turn; the page change that follows must not animate again.
        private var settledTurnDeadline: Date?

        init(_ value: SimulationPageTransition) { self.value = value }

        func update(_ newValue: SimulationPageTransition, controller: UIPageViewController) {
            if interacting || animating || committing { pending = newValue; return }
            let changed = value.page != newValue.page
            let forward = newValue.page >= value.page
            value = newValue
            if changed {
                let settled = settledTurnDeadline.map { Date() < $0 } ?? false
                settledTurnDeadline = nil
                install(controller, animated: !settled, forward: forward)
            }
            else {
                controller.dataSource = value.enabled ? self : nil
                faces[0]?.rootView = AnyView(value.content())
                faces[1]?.rootView = back(value.content())
                for (index, face) in faces where index != 0 && index != 1 {
                    face.rootView = index < 0 ? (index == -2 ? AnyView(value.previous()) : back(value.previous())) :
                        (index == 2 ? AnyView(value.next()) : back(value.next()))
                }
                disableNativeTaps(controller)
            }
        }

        func install(_ controller: UIPageViewController, animated: Bool, forward: Bool = true) {
            faces = [:]
            controller.dataSource = value.enabled ? self : nil
            let front = face(0), reverse = face(1)
            animating = animated
            controller.setViewControllers(animated ? [front, reverse] : [front], direction: forward ? .forward : .reverse, animated: animated) { [weak self, weak controller] _ in
                guard let self, let controller else { return }
                self.animating = false
                self.applyPending(controller)
            }
            disableNativeTaps(controller)
        }

        private func disableNativeTaps(_ controller: UIPageViewController) {
            for gesture in controller.gestureRecognizers where gesture is UITapGestureRecognizer { gesture.isEnabled = false }
        }

        private func back<V: View>(_ view: V) -> AnyView {
            AnyView(value.paperColor.overlay(view.scaleEffect(x: -1, y: 1).opacity(0.12)).accessibilityHidden(true))
        }

        private func face(_ index: Int) -> Face {
            if let cached = faces[index] { return cached }
            let view: AnyView
            switch index {
            case -2: view = AnyView(value.previous())
            case -1: view = back(value.previous())
            case 0: view = AnyView(value.content())
            case 1: view = back(value.content())
            case 2: view = AnyView(value.next())
            default: view = back(value.next())
            }
            let controller = Face(index: index, rootView: view)
            faces[index] = controller
            return controller
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard value.enabled, !committing, let current = viewController as? Face else { return nil }
            let index = current.index - 1
            guard index >= -2, index >= 0 || value.canPrevious else { return nil }
            return face(index)
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard value.enabled, !committing, let current = viewController as? Face else { return nil }
            let index = current.index + 1
            guard index <= 3, index <= 1 || value.canNext else { return nil }
            return face(index)
        }

        func pageViewController(_ controller: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            interacting = true
        }

        func pageViewController(_ controller: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            interacting = false
            guard completed, let visible = controller.viewControllers?.compactMap({ $0 as? Face }).first,
                  visible.index != 0 else { applyPending(controller); return }
            committing = true
            task = Task { @MainActor [weak self, weak controller] in
                guard let self, let controller else { return }
                let previousPage = value.page
                let turned = await value.turn(visible.index > 0)
                guard !Task.isCancelled else { return }
                committing = false
                if let pending { value = pending; self.pending = nil }
                settledTurnDeadline = turned && value.page == previousPage ? Date().addingTimeInterval(1) : nil
                install(controller, animated: false)
                task = nil
            }
        }

        private func applyPending(_ controller: UIPageViewController) {
            guard !interacting, !committing, !animating, let pending else { return }
            self.pending = nil
            update(pending, controller: controller)
        }
    }
}
