import Foundation
import Observation

enum ReaderTapAction: Int, Equatable { case menu = 0, next = 1, previous = 2 }

enum ReaderTouchMap {
    static func action(x: Double, y: Double, width: Double, height: Double) -> ReaderTapAction? {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0, x >= 0, y >= 0, x < width, y < height else { return nil }
        let column = x < width * 0.33 ? 0 : (x < width * 0.66 ? 1 : 2)
        let row = y < height * 0.33 ? 0 : (y < height * 0.66 ? 1 : 2)
        return [.previous, .previous, .next, .previous, .menu, .next, .previous, .next, .next][row * 3 + column]
    }
}

enum AutoReadStep {
    static func distance(elapsed: Double, speed: Double, height: Double) -> Double {
        guard elapsed.isFinite, speed.isFinite, height.isFinite, elapsed > 0, speed > 0, height > 0 else { return 0 }
        return height * elapsed / speed
    }
}

@Observable
@MainActor
final class AutoReadController {
    private(set) var isRunning = false
    private(set) var progress: Double = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(speed: Double, advance: @escaping @MainActor () async -> Bool) {
        stop()
        guard speed.isFinite, speed > 0 else { return }
        isRunning = true
        task = Task { [weak self] in
            let clock = ContinuousClock()
            var previous = clock.now
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 33_333_333) } catch { return }
                guard let self, isRunning else { return }
                let now = clock.now
                let elapsed = previous.duration(to: now).components
                previous = now
                progress += AutoReadStep.distance(elapsed: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18, speed: speed, height: 1)
                if progress >= 1 {
                    progress = 1
                    let advanced = await advance()
                    guard !Task.isCancelled else { return }
                    guard advanced else { stop(); return }
                    progress = 0
                    previous = clock.now
                }
            }
        }
    }

    func stop() { task?.cancel(); task = nil; isRunning = false; progress = 0 }
    deinit { task?.cancel() }
}
