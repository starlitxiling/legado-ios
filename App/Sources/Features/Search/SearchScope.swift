import Foundation
import LegadoCore

struct SearchScope: Equatable {
    var value = ""
    var sourceURL: String? {
        guard let separator = value.range(of: "::") else { return nil }
        return String(value[separator.upperBound...])
    }
    var groups: [String] {
        sourceURL == nil ? value.split(separator: ",").map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } : []
    }
    var display: String {
        if value.isEmpty { return "全部书源" }
        if let separator = value.range(of: "::") { return String(value[..<separator.lowerBound]) }
        return value
    }
    static func source(_ source: BookSourceSummary) -> SearchScope {
        .init(value: source.name.replacingOccurrences(of: ":", with: "") + "::" + source.id)
    }
    func resolve(_ sources: [BookSourceSummary]) -> (scope: SearchScope, sources: [BookSourceSummary]) {
        if let sourceURL, let source = sources.first(where: { $0.id == sourceURL }) { return (self, [source]) }
        let enabled = sources.filter(\.enabled)
        if sourceURL == nil, !groups.isEmpty {
            let valid = groups.filter { group in enabled.contains { $0.groups.contains(group) } }
            if !valid.isEmpty {
                return (.init(value: valid.joined(separator: ",")), enabled.filter { !Set($0.groups).isDisjoint(with: valid) })
            }
        }
        return (.init(), enabled)
    }
}

enum SearchResultFilter {
    static func allows(_ book: SearchBook, words: String) -> Bool {
        let blocked = words.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return !blocked.contains { word in
            [book.name, book.author, book.kind].contains { ($0 ?? "").range(of: word, options: .caseInsensitive) != nil }
        }
    }
}
