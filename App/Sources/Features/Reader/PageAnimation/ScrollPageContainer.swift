import SwiftUI
import UIKit

struct ReaderScrollPage: Identifiable {
    let id: Int
    let height: Double
    let content: AnyView
}

struct ScrollPageContainer: UIViewControllerRepresentable {
    let pages: [ReaderScrollPage]
    let location: Int
    let progress: Double
    let enabled: Bool
    let select: (Int) async -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.accessibilityIdentifier = "reader.scroll"
        scroll.delegate = context.coordinator
        scroll.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(scroll)
        let host = UIHostingController(rootView: AnyView(EmptyView()))
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
        context.coordinator.update(self)
    }

    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        coordinator.task?.cancel()
        coordinator.scroll?.delegate = nil
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var host: UIHostingController<AnyView>?
        weak var scroll: UIScrollView?
        var task: Task<Void, Never>?
        private var value: ScrollPageContainer
        private var displayed: [ReaderScrollPage] = []
        private var reported: Int?
        private var pending: Int?
        private var updating = false
        private var initialized = false
        private var geometry: ReaderScrollGeometry { ReaderScrollGeometry(items: displayed.map { ($0.id, $0.height) }) }
        init(_ value: ScrollPageContainer) { self.value = value }

        func update(_ newValue: ScrollPageContainer) {
            guard let scroll, !newValue.pages.isEmpty else { value = newValue; return }
            // Keep the preceding chapter during a fling so UIKit retains its deceleration origin.
            let moving = scroll.isDragging || scroll.isDecelerating || task != nil
            let anchor = geometry.anchor(at: scroll.contentOffset.y)
            let externalSeek = !initialized || newValue.location != value.location && newValue.location != reported && task == nil
            let previousProgress = value.progress
            value = newValue
            guard value.enabled || !initialized else { return }
            updating = true
            if moving, let first = value.pages.first {
                displayed = displayed.filter { $0.id < first.id } + value.pages
            } else { displayed = value.pages }
            host?.rootView = AnyView(VStack(spacing: 0) {
                ForEach(displayed) { page in page.content.frame(height: page.height, alignment: .top) }
            })
            host?.view.invalidateIntrinsicContentSize()
            scroll.superview?.layoutIfNeeded()
            var offset = scroll.contentOffset.y
            if externalSeek {
                offset = geometry.offset(for: .init(id: value.location, distance: 0)) ?? offset
                reported = value.location
            } else if let anchor { offset = geometry.offset(for: anchor) ?? offset }
            if value.progress > previousProgress, !moving {
                offset += (value.progress - previousProgress) * scroll.bounds.height
            }
            if abs(offset - scroll.contentOffset.y) > 0.5 { scroll.bounds.origin.y = max(0, offset) }
            initialized = true; updating = false
            updateAccessibility()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !updating, initialized, value.enabled else { return }
            updateAccessibility()
            guard value.progress == 0, let location = geometry.anchor(at: scrollView.contentOffset.y + 1)?.id,
                  location != reported else { return }
            pending = location
            drain()
        }

        private func drain() {
            guard task == nil, let target = pending else { return }
            pending = nil; reported = target
            task = Task { @MainActor [weak self] in
                guard let self else { return }
                await value.select(target)
                guard !Task.isCancelled else { return }
                task = nil
                if pending != nil { drain() }
                else { update(value) }
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { update(value) }
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { update(value) }

        private func updateAccessibility() {
            guard let scroll, let id = geometry.anchor(at: scroll.contentOffset.y + 1)?.id else { return }
            scroll.accessibilityValue = "第 \(id / 1_000_000 + 1) 章，第 \(id % 1_000_000 + 1) 页"
        }
    }
}
