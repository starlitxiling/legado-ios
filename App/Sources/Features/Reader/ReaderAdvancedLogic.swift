import Foundation
import Observation

enum ReaderTapAction: Int, Equatable, CaseIterable {
    case noAction = -1, menu, next, previous, nextChapter, previousChapter
    case previousParagraph, nextParagraph, bookmark, editContent, toggleReplace, toc, search, sync, readAloud

    var title: String {
        switch self {
        case .noAction: return "无"
        case .menu: return "菜单"
        case .next: return "下一页"
        case .previous: return "上一页"
        case .nextChapter: return "下一章"
        case .previousChapter: return "上一章"
        case .previousParagraph: return "朗读上一段"
        case .nextParagraph: return "朗读下一段"
        case .bookmark: return "添加书签"
        case .editContent: return "编辑内容"
        case .toggleReplace: return "替换开关"
        case .toc: return "目录"
        case .search: return "全文搜索"
        case .sync: return "同步进度"
        case .readAloud: return "朗读暂停继续"
        }
    }
}

enum ReaderTouchMap {
    static let keys = ["clickActionTL", "clickActionTC", "clickActionTR", "clickActionML", "clickActionMC", "clickActionMR", "clickActionBL", "clickActionBC", "clickActionBR"]
    static let defaultActions: [ReaderTapAction] = [.previous, .previous, .next, .previous, .menu, .next, .previous, .next, .next]

    static func normalized(_ actions: [ReaderTapAction]) -> [ReaderTapAction] {
        guard actions.count == 9 else { return defaultActions }
        var result = actions
        if !result.contains(.menu) { result[4] = .menu }
        return result
    }

    static func load(from defaults: UserDefaults = .standard) -> [ReaderTapAction] {
        normalized(keys.enumerated().map { index, key in
            defaults.object(forKey: key).flatMap { ($0 as? NSNumber).flatMap { ReaderTapAction(rawValue: $0.intValue) } } ?? defaultActions[index]
        })
    }

    static func save(_ actions: [ReaderTapAction], to defaults: UserDefaults = .standard) {
        for (key, action) in zip(keys, normalized(actions)) { defaults.set(action.rawValue, forKey: key) }
    }

    static func action(x: Double, y: Double, width: Double, height: Double,
                       actions: [ReaderTapAction] = defaultActions) -> ReaderTapAction? {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0, x >= 0, y >= 0, x < width, y < height else { return nil }
        let column = min(2, Int(x / width * 3))
        let row = min(2, Int(y / height * 3))
        return normalized(actions)[row * 3 + column]
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
