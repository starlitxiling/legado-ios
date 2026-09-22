import Foundation

enum ReaderScrollStep {
    static func resolve(offset: Double, height: Double) -> (pages: Int, remainder: Double) {
        guard offset.isFinite, height.isFinite, height > 0 else { return (0, 0) }
        if offset > height {
            let pages = Int(ceil(offset / height) - 1)
            return (pages, offset - Double(pages) * height)
        }
        if offset < 0 { return (-1, offset + height) }
        return (0, offset)
    }
}

struct ReaderPresentationState {
    enum Animation: Int { case cover, slide, simulation, scroll, none }
    let animation: Animation
    let revealHeight: Double
    var lineOffset: Double { max(0, revealHeight - 1) }

    init(mode: Int, progress: Double, height: Double) {
        animation = Animation(rawValue: mode) ?? .cover
        revealHeight = animation == .scroll || !progress.isFinite || !height.isFinite ? 0 : max(0, height) * min(1, max(0, progress))
    }
}

struct ReaderHorizontalDrag {
    let translation: Double
    let projected: Double
    let width: Double

    func destination(canPrevious: Bool, canNext: Bool) -> Bool? {
        guard width.isFinite, width > 0, translation.isFinite, projected.isFinite,
              abs(translation) >= 20 else { return nil }
        let forward = translation < 0
        guard forward ? canNext : canPrevious else { return nil }
        let distance = abs(translation) >= width / 3
        let momentum = translation * projected > 0 && abs(projected) >= width * 0.65
        return distance || momentum ? forward : nil
    }

    func offsets(slide: Bool) -> (previous: Double, current: Double, next: Double) {
        let delta = min(width, max(-width, translation))
        return (-width + max(slide ? -width : 0, delta), slide ? delta : 0,
                width + min(slide ? width : 0, delta))
    }
}
