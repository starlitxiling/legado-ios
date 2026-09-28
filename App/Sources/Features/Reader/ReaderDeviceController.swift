import UIKit
import Observation

@Observable @MainActor
final class ReaderDeviceController {
    static var orientationMask: UIInterfaceOrientationMask = .allButUpsideDown
    var brightness: Double = 0.5
    var automaticBrightness = true
    var brightnessOnRight = false
    private var originalBrightness: CGFloat?
    private var originalIdle: Bool?
    private var idleTask: Task<Void, Never>?
    private var keepLight = 0

    func begin(_ configuration: ReaderBehaviorConfiguration) {
        if originalBrightness == nil {
            originalBrightness = screen?.brightness
            originalIdle = UIApplication.shared.isIdleTimerDisabled
            brightness = Double(screen?.brightness ?? 0.5)
            brightnessOnRight = UserDefaults.standard.bool(forKey: "brightnessOnRight")
        }
        update(configuration)
    }
    func update(_ configuration: ReaderBehaviorConfiguration) {
        keepLight = Int(configuration.string("keep_light")) ?? 0
        interaction()
        switch configuration.string("screenOrientation") {
        case "1": Self.orientationMask = .portrait
        case "2": Self.orientationMask = .landscapeRight
        case "3": Self.orientationMask = .all
        case "4": Self.orientationMask = .portraitUpsideDown
        case "5": Self.orientationMask = .landscapeLeft
        default: Self.orientationMask = .allButUpsideDown
        }
        updateOrientation()
    }
    func interaction() {
        idleTask?.cancel()
        guard originalIdle != nil else { return }
        UIApplication.shared.isIdleTimerDisabled = keepLight != 0 || originalIdle == true
        if keepLight > 0 {
            let seconds = keepLight
            idleTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                guard let self else { return }
                UIApplication.shared.isIdleTimerDisabled = originalIdle ?? false
            }
        }
    }
    func setBrightness(_ value: Double) {
        automaticBrightness = false
        brightness = min(1, max(0, value)); screen?.brightness = brightness
    }
    func toggleAutomaticBrightness() {
        automaticBrightness.toggle()
        if automaticBrightness, let originalBrightness { screen?.brightness = originalBrightness; brightness = originalBrightness }
        else { screen?.brightness = brightness }
    }
    func swapBrightnessSide() {
        brightnessOnRight.toggle(); UserDefaults.standard.set(brightnessOnRight, forKey: "brightnessOnRight")
    }
    func end() {
        idleTask?.cancel(); idleTask = nil
        if let originalBrightness { screen?.brightness = originalBrightness }
        if let originalIdle { UIApplication.shared.isIdleTimerDisabled = originalIdle }
        originalBrightness = nil; originalIdle = nil
        Self.orientationMask = .allButUpsideDown; updateOrientation()
    }
    private var scene: UIWindowScene? { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive } }
    private var screen: UIScreen? { scene?.screen }
    private func updateOrientation() {
        guard let scene else { return }
        scene.windows.first(where: \.isKeyWindow)?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: Self.orientationMask)) { error in
            NSLog("Reader orientation request was not applied: %@", error.localizedDescription)
        }
    }
}

@MainActor
final class ReaderProgressBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Reader progress") { [weak self] in
            Task { @MainActor in self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
