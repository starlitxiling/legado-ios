import Foundation

enum BookshelfLayout: Int, CaseIterable, Sendable {
    case list, compact, grid2, grid3, grid4, grid5, grid6
    var columns: Int? { rawValue >= 2 ? rawValue : nil }
    var title: String {
        switch self {
        case .list: return "列表"
        case .compact: return "紧凑列表"
        default: return "网格 \(rawValue) 列"
        }
    }
    var coverWidth: Double { self == .compact ? 48 : 66 }
    var coverHeight: Double { self == .compact ? 64 : 90 }
}

enum BookshelfProgressMode: Int, CaseIterable, Sendable {
    case hidden, standard, enhanced
    init(storedMode: Int?, legacyEnabled: Bool?) {
        if let storedMode { self = Self(rawValue: min(2, max(0, storedMode)))! }
        else { self = legacyEnabled == false ? .hidden : .standard }
    }
    var thickness: Double { self == .enhanced ? 4 : 2 }
    var title: String {
        switch self { case .hidden: return "隐藏"; case .standard: return "标准"; case .enhanced: return "增强" }
    }
}

struct BookshelfBookMetrics: Equatable, Sendable {
    let unread: Int
    let progress: Double?
    init(total: Int, chapter: Int, position: Int) {
        let count = max(0, total), index = max(0, chapter)
        unread = count > index ? count - index - 1 : 0
        if chapter == 0 && position == 0 { progress = nil }
        else if count <= 1 { progress = 1 }
        else { progress = min(1, max(0, Double(chapter) / Double(count - 1))) }
    }
}
