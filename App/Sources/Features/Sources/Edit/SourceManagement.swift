import Foundation
import LegadoCore

enum SourceSort: String, CaseIterable, Identifiable {
    case custom = "自定义", name = "名称", url = "地址", weight = "权重", update = "更新时间", respond = "响应时间", enabled = "启用状态"
    var id: String { rawValue }
}

enum SourceManagement {
    static func sorted(_ sources: [BookSourceRow], by sort: SourceSort, ascending: Bool = true) -> [BookSourceRow] {
        sources.enumerated().sorted { left, right in
            let a = left.element, b = right.element
            let comparison: ComparisonResult
            func number<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
                a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
            }
            switch sort {
            case .custom: comparison = number(a.customOrder, b.customOrder)
            case .name: comparison = a.bookSourceName.compare(b.bookSourceName, locale: Locale(identifier: "zh_Hans_CN"))
            case .url: comparison = number(a.bookSourceUrl, b.bookSourceUrl)
            case .weight: comparison = number(a.weight, b.weight)
            case .update: comparison = number(b.lastUpdateTime, a.lastUpdateTime)
            case .respond: comparison = number(a.respondTime, b.respondTime)
            case .enabled:
                if a.enabled == b.enabled {
                    let result = a.bookSourceName.compare(b.bookSourceName, locale: Locale(identifier: "zh_Hans_CN"))
                    return result == .orderedSame ? left.offset < right.offset : result == .orderedAscending
                }
                comparison = a.enabled ? .orderedAscending : .orderedDescending
            }
            if comparison == .orderedSame {
                return sort == .custom && !ascending ? left.offset > right.offset : left.offset < right.offset
            }
            return comparison == (ascending ? .orderedAscending : .orderedDescending)
        }.map(\.element)
    }

    static func setEnabled(_ sources: [BookSourceRow], selected: Set<String>, enabled: Bool) -> [BookSourceRow] {
        sources.map { row in
            var value = row
            if selected.contains(row.bookSourceUrl) { value.enabled = enabled }
            return value
        }
    }

    static func move(_ sources: [BookSourceRow], selected: Set<String>, toTop: Bool) throws -> [BookSourceRow] {
        let ordered = sorted(sources.filter { selected.contains($0.bookSourceUrl) }, by: .custom)
        let edge = toTop ? (sources.map(\.customOrder).min() ?? 0) : (sources.map(\.customOrder).max() ?? 0)
        var orders: [String: Int] = [:]
        for (index, row) in ordered.enumerated() {
            let result = edge.addingReportingOverflow(toTop ? -index - 1 : index + 1)
            guard !result.overflow, Int32(exactly: result.partialValue) != nil else { throw SourceEditError.orderOverflow }
            orders[row.bookSourceUrl] = result.partialValue
        }
        return sources.map { row in
            var value = row
            if let order = orders[row.bookSourceUrl] { value.customOrder = order }
            return value
        }
    }

    static func setExploreEnabled(_ sources: [BookSourceRow], selected: Set<String>, enabled: Bool) -> [BookSourceRow] {
        sources.map { row in
            var value = row
            if selected.contains(row.bookSourceUrl) { value.enabledExplore = enabled }
            return value
        }
    }

    static func groups(_ text: String?) -> [String] {
        var seen = Set<String>()
        return (text ?? "").components(separatedBy: CharacterSet(charactersIn: ",;，；\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
