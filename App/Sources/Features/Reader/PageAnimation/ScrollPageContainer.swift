import SwiftUI
import UIKit

struct ScrollPageContainer<Content: View>: UIViewControllerRepresentable {
    let progress: Double
    let page: Int
    let content: Content
    let turn: (Bool) async -> Bool

    init(progress: Double, page: Int, turn: @escaping (Bool) async -> Bool, @ViewBuilder content: () -> Content) {
        self.progress = progress; self.page = page; self.turn = turn; self.content = content()
    }

    func makeCoordinator() -> Coordinator { Coordinator(turn: turn) }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.delegate = context.coordinator
        scroll.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(scroll)
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        controller.addChild(host); scroll.addSubview(host.view); host.didMove(toParent: controller)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: controller.view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            host.view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        context.coordinator.host = host
        context.coordinator.scroll = scroll
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.host?.rootView = content
        context.coordinator.turn = turn
        context.coordinator.update(page: page, progress: progress)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var host: UIHostingController<Content>?
        weak var scroll: UIScrollView?
        var turn: (Bool) async -> Bool
        private var page: Int?
        private var progress: Double = 0
        private var pendingTurn = false
        private var updating = false
        init(turn: @escaping (Bool) async -> Bool) { self.turn = turn }

        func update(page: Int, progress: Double) {
            guard let scroll else { return }
            updating = true
            var offset = scroll.contentOffset.y
            if let previous = self.page, previous != page {
                if pendingTurn || self.progress > 0 {
                    offset += page > previous ? -scroll.bounds.height : scroll.bounds.height
                } else { offset = 0 }
                pendingTurn = false
            } else if progress > self.progress, !scroll.isDragging {
                offset += (progress - self.progress) * scroll.bounds.height
            }
            self.page = page; self.progress = progress
            if offset != scroll.contentOffset.y { scroll.setContentOffset(CGPoint(x: 0, y: max(0, offset)), animated: false) }
            updating = false
            checkBoundary(scroll)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { checkBoundary(scrollView) }

        private func checkBoundary(_ scrollView: UIScrollView) {
            guard !updating, !pendingTurn, page != nil, progress == 0 else { return }
            let step = ReaderScrollStep.resolve(offset: scrollView.contentOffset.y, height: scrollView.bounds.height)
            if step.pages != 0 {
                pendingTurn = true
                Task { [weak self, weak scrollView] in
                    guard let self else { return }
                    if !(await turn(step.pages > 0)) {
                        updating = true
                        scrollView?.setContentOffset(.zero, animated: false)
                        updating = false; pendingTurn = false
                    }
                }
            }
        }
    }
}
