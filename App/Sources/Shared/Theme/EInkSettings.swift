import Foundation
import LegadoCore

/// iOS-only options that make the e-ink theme feel like a real e-paper reader.
struct EInkSettings: Equatable {
    enum Paper: String, CaseIterable, Identifiable {
        case style, white, paper, warm
        var id: String { rawValue }
        var title: String {
            switch self {
            case .style: return "跟随阅读样式"
            case .white: return "纯白"
            case .paper: return "纸白"
            case .warm: return "暖纸"
            }
        }
        /// nil keeps the reading style's own e-ink background.
        var argb: UInt32? {
            switch self {
            case .style: return nil
            case .white: return 0xFFFFFFFF
            case .paper: return 0xFFF2F1EC
            case .warm: return 0xFFEDE6D6
            }
        }
    }

    enum ImageMode: String, CaseIterable, Identifiable {
        case gray, levels, dither, threshold
        var id: String { rawValue }
        var title: String {
            switch self {
            case .gray: return "灰度"
            case .levels: return "16 级灰阶"
            case .dither: return "黑白抖动"
            case .threshold: return "黑白阈值"
            }
        }
    }

    static let refreshIntervalKey = "eInkRefreshInterval"
    static let paperKey = "eInkPaper"
    static let textWeightKey = "eInkTextWeight"
    static let sharpTextKey = "eInkSharpText"
    static let imageModeKey = "eInkImageMode"
    static let thresholdKey = "eInkImageThreshold"
    static let hideStatusBarKey = "eInkHideStatusBar"

    static let defaults: [String: AndroidPreferenceValue] = [
        refreshIntervalKey: .int(6), paperKey: .string(Paper.paper.rawValue), textWeightKey: .int(1),
        sharpTextKey: .boolean(false), imageModeKey: .string(ImageMode.levels.rawValue), thresholdKey: .int(128),
        hideStatusBarKey: .boolean(false)
    ]

    /// Pages between full black-white flashes; 0 disables them.
    var refreshInterval = 6
    var paper = Paper.paper
    /// 0 normal, 1 darker, 2 darkest.
    var textWeight = 1
    var sharpText = false
    var imageMode = ImageMode.levels
    var threshold = 128
    /// Hide the system status bar while reading. Off by default so the e-ink layout matches the other
    /// themes, with the reading header below the Dynamic Island.
    var hideStatusBar = false

    init() {}

    init(values: [String: AndroidPreferenceValue]) {
        func int(_ key: String) -> Int? { if case .int(let value) = values[key] { return Int(value) }; return nil }
        func string(_ key: String) -> String? { if case .string(let value) = values[key] { return value }; return nil }
        if let value = int(Self.refreshIntervalKey) { refreshInterval = min(50, max(0, value)) }
        if let value = string(Self.paperKey).flatMap(Paper.init(rawValue:)) { paper = value }
        if let value = int(Self.textWeightKey) { textWeight = min(2, max(0, value)) }
        if case .boolean(let value) = values[Self.sharpTextKey] { sharpText = value }
        if let value = string(Self.imageModeKey).flatMap(ImageMode.init(rawValue:)) { imageMode = value }
        if let value = int(Self.thresholdKey) { threshold = min(250, max(5, value)) }
        if case .boolean(let value) = values[Self.hideStatusBarKey] { hideStatusBar = value }
    }

    /// CoreText stroke width (negative = fill and stroke) that thickens glyphs like an e-reader's "darken text".
    var strokeWidth: Double { [0, -2.5, -5][textWeight] }
}

/// Counts page turns and reports when a full refresh flash is due, like an e-paper panel clearing ghosting.
struct EInkRefreshCounter: Equatable {
    private(set) var turns = 0

    mutating func turn(interval: Int) -> Bool {
        guard interval > 0 else { turns = 0; return false }
        turns += 1
        guard turns >= interval else { return false }
        turns = 0
        return true
    }

    mutating func reset() { turns = 0 }
}
