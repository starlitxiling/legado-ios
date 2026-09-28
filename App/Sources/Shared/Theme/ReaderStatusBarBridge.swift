import SwiftUI
import UIKit

struct ReaderStatusBarBridge: UIViewRepresentable {
    let darkIcons: Bool?
    let colorScheme: ColorScheme?
    var phaseChanged: (ScenePhase) -> Void = { _ in }

    func makeUIView(context: Context) -> BridgeView { BridgeView() }
    func updateUIView(_ view: BridgeView, context: Context) {
        view.phaseChanged = phaseChanged
        view.darkIcons = darkIcons
        view.interfaceStyle = colorScheme.map { $0 == .dark ? .dark : .light } ?? .unspecified
        view.apply()
    }

    final class BridgeView: UIView {
        var darkIcons: Bool?
        var phaseChanged: (ScenePhase) -> Void = { _ in }
        private var observers: [NSObjectProtocol] = []
        var interfaceStyle: UIUserInterfaceStyle = .unspecified
        override func didMoveToWindow() {
            super.didMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            if let scene = window?.windowScene {
                for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification, UIScene.willEnterForegroundNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: scene, queue: .main) { [weak self] notification in
                        MainActor.assumeIsolated {
                            let phase: ScenePhase = notification.name == UIScene.didActivateNotification ? .active : notification.name == UIScene.didEnterBackgroundNotification ? .background : .inactive
                            self?.phaseChanged(phase)
                        }
                    })
                }
            }
            apply()
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        func apply() {
            guard let window, let root = window.rootViewController else { return }
            // The SwiftUI host is a child now, so forward the owning UIKit scene lifecycle.
            let phase: ScenePhase = window.windowScene?.activationState == .foregroundActive ? .active : window.windowScene?.activationState == .background ? .background : .inactive
            DispatchQueue.main.async { [weak self] in self?.phaseChanged(phase) }
            if let controller = root as? ReaderStatusBarController {
                controller.darkIcons = darkIcons
                controller.overrideUserInterfaceStyle = interfaceStyle
            }
            else {
                // UIKit asks the window root for status style; a background child cannot own it.
                let controller = ReaderStatusBarController(content: root)
                controller.darkIcons = darkIcons
                controller.overrideUserInterfaceStyle = interfaceStyle
                window.rootViewController = controller
            }
        }
    }
}

final class ReaderStatusBarController: UIViewController {
    let content: UIViewController
    var darkIcons: Bool? {
        didSet { if darkIcons != oldValue { setNeedsStatusBarAppearanceUpdate() } }
    }

    init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content.view)
        NSLayoutConstraint.activate([
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        content.didMove(toParent: self)
    }

    override var childForStatusBarStyle: UIViewController? { darkIcons == nil ? content : nil }
    override var preferredStatusBarStyle: UIStatusBarStyle { darkIcons == true ? .darkContent : .lightContent }
    override var childForStatusBarHidden: UIViewController? { content }
    override var childForHomeIndicatorAutoHidden: UIViewController? { content }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { content }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { content.supportedInterfaceOrientations }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { content.preferredInterfaceOrientationForPresentation }
    override var shouldAutorotate: Bool { content.shouldAutorotate }
}
