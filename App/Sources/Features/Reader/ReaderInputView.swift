import SwiftUI
import UIKit

struct ReaderInputView: UIViewRepresentable {
    let configuration: ReaderBehaviorConfiguration
    let enabled: Bool
    let scrollMode: Bool
    var interactivePaging = false
    let tap: (CGPoint, Int) -> Void
    let longPress: (CGPoint) -> Void
    let turn: (Bool) -> Void
    let bookmark: () -> Void
    let preview: () -> Void

    func makeUIView(context: Context) -> InputSurface { InputSurface() }
    func updateUIView(_ view: InputSurface, context: Context) {
        view.input = self
        view.updateRecognizers()
    }
    static func dismantleUIView(_ view: InputSurface, coordinator: ()) { view.detach() }

    final class InputSurface: UIView, UIGestureRecognizerDelegate {
        var input: ReaderInputView?
        private weak var observedWindow: UIWindow?
        private var began: TimeInterval = 0
        private var wheelDistance: CGFloat = 0
        private lazy var single = ClickRecognizer(target: self, action: #selector(singleTap(_:)))
        private lazy var double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        private lazy var hold = UILongPressGestureRecognizer(target: self, action: #selector(longTap(_:)))
        private lazy var drag = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        private lazy var wheel = UIPanGestureRecognizer(target: self, action: #selector(scroll(_:)))
        private lazy var two = UITapGestureRecognizer(target: self, action: #selector(twoTap(_:)))
        private var recognizers: [UIGestureRecognizer] { [single, double, hold, drag, wheel, two] }
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear; isUserInteractionEnabled = false
            double.numberOfTapsRequired = 2
            two.numberOfTouchesRequired = 2
            hold.minimumPressDuration = 0.45
            drag.maximumNumberOfTouches = 1
            wheel.minimumNumberOfTouches = 0
            wheel.maximumNumberOfTouches = 0
            wheel.allowedScrollTypesMask = .all
            wheel.allowedTouchTypes = []
            single.require(toFail: double)
            for recognizer in recognizers { recognizer.delegate = self; recognizer.cancelsTouchesInView = false }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            observedWindow = window
            for recognizer in recognizers { window?.addGestureRecognizer(recognizer) }
            updateRecognizers()
        }
        func detach() {
            for recognizer in recognizers { observedWindow?.removeGestureRecognizer(recognizer) }
            observedWindow = nil
        }
        func updateRecognizers() {
            guard let input else { return }
            for recognizer in recognizers { recognizer.isEnabled = input.enabled }
            double.isEnabled = input.enabled && (input.configuration.string("highlightActionTrigger") == "doubleTap" || input.configuration.string("clickImgWay") == "4")
            two.isEnabled = input.enabled && input.configuration.boolean("twoFingerReplacePreview")
            wheel.isEnabled = input.enabled && input.configuration.boolean("mouseWheelPage")
            single.tolerance = CGFloat(input.configuration.integer("pageTouchClick") == 0 ? 10 : input.configuration.integer("pageTouchClick"))
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            input?.enabled == true && bounds.contains(touch.location(in: self))
        }
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            input?.enabled == true && bounds.contains(gestureRecognizer.location(in: self))
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc private func singleTap(_ recognizer: UIGestureRecognizer) { input?.tap(recognizer.location(in: self), 1) }
        @objc private func doubleTap(_ recognizer: UIGestureRecognizer) { input?.tap(recognizer.location(in: self), 2) }
        @objc private func twoTap(_ recognizer: UIGestureRecognizer) { input?.preview() }
        @objc private func longTap(_ recognizer: UIGestureRecognizer) {
            if recognizer.state == .began { input?.longPress(recognizer.location(in: self)) }
        }
        @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
            guard let input else { return }
            if recognizer.state == .began { began = Date.timeIntervalSinceReferenceDate }
            guard recognizer.state == .ended else { return }
            let delta = recognizer.translation(in: self)
            switch input.configuration.gesture(x: delta.x, y: delta.y, duration: Date.timeIntervalSinceReferenceDate - began,
                                                           scale: traitCollection.displayScale) {
            case .next: if !input.scrollMode && !input.interactivePaging { input.turn(true) }
            case .previous: if !input.scrollMode && !input.interactivePaging { input.turn(false) }
            case .bookmark: input.bookmark()
            default: break
            }
        }
        @objc private func scroll(_ recognizer: UIPanGestureRecognizer) {
            guard let input else { return }
            if recognizer.state == .began { wheelDistance = 0 }
            let delta = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
            wheelDistance += (abs(delta.y) >= abs(delta.x) ? delta.y : delta.x) * CGFloat(input.configuration.integer("mouseWheelScrollSpeed")) / 100
            if abs(wheelDistance) >= 60 { input.turn(wheelDistance < 0); wheelDistance = 0 }
        }
    }

    final class ClickRecognizer: UIGestureRecognizer {
        var tolerance: CGFloat = 10
        private var start = CGPoint.zero
        private var time: TimeInterval = 0
        private var current = CGPoint.zero
        override func location(in view: UIView?) -> CGPoint { self.view?.convert(current, to: view) ?? current }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard touches.count == 1, event.allTouches?.count == 1, let touch = touches.first else { state = .failed; return }
            start = touch.location(in: view); current = start; time = touch.timestamp
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch = touches.first else { return }
            let point = touch.location(in: view); current = point
            if abs(point.x - start.x) > tolerance || abs(point.y - start.y) > tolerance { state = .failed }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch = touches.first, touch.timestamp - time < 0.4 else { state = .failed; return }
            let point = touch.location(in: view); current = point
            state = abs(point.x - start.x) <= tolerance && abs(point.y - start.y) <= tolerance ? .recognized : .failed
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    }
}
