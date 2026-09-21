import SwiftUI
import UIKit

struct ReaderNavigationGuard: UIViewControllerRepresentable {
    let disabled: Bool
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.disabled = disabled
        controller.apply()
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.restore() }

    final class Controller: UIViewController {
        var disabled = false
        private weak var gesture: UIGestureRecognizer?
        private var originalEnabled: Bool?
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply() }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); apply() }
        func apply() {
            guard let current = navigationController?.interactivePopGestureRecognizer else { return }
            if gesture !== current {
                restore(); gesture = current; originalEnabled = current.isEnabled
            }
            current.isEnabled = disabled ? false : (originalEnabled ?? true)
        }
        func restore() {
            if let originalEnabled { gesture?.isEnabled = originalEnabled }
            gesture = nil; originalEnabled = nil
        }
    }
}
