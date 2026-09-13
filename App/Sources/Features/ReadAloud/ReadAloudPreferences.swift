import Foundation
import Observation

@Observable
final class ReadAloudPreferences {
    var rate: Double { didSet { defaults.set(rate, forKey: "readAloud.rate") } }
    var volume: Double { didSet { defaults.set(volume, forKey: "readAloud.volume") } }
    var sourceID: Int64? { didSet { defaults.set(sourceID, forKey: "readAloud.sourceID") } }
    var readAloudByPage: Bool { didSet { defaults.set(readAloudByPage, forKey: "readAloud.byPage") } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rate = (defaults.object(forKey: "readAloud.rate") as? Double).map { min(3, max(0.5, $0)) } ?? 1
        volume = (defaults.object(forKey: "readAloud.volume") as? Double).map { min(1, max(0, $0)) } ?? 1
        sourceID = (defaults.object(forKey: "readAloud.sourceID") as? NSNumber)?.int64Value
        readAloudByPage = defaults.bool(forKey: "readAloud.byPage")
    }
    static func httpSpeed(_ rate: Double) -> Int { Int((rate * 10).rounded()) }
}
