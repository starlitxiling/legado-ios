import Foundation
import LegadoCore

struct CoverCandidate: Equatable, Identifiable {
    static let defaultCoverURL = "use_default_cover"
    let originName: String
    let coverUrl: String
    let origin: String?
    var id: String { coverUrl }

    static func merge(name: String, author: String, rule: String?, results: [SearchBook]) -> [CoverCandidate] {
        var seen: Set<String> = [defaultCoverURL]
        var items = [CoverCandidate(originName: "默认封面", coverUrl: defaultCoverURL, origin: nil)]
        if let rule, !rule.isEmpty, seen.insert(rule).inserted {
            items.append(CoverCandidate(originName: "封面规则", coverUrl: rule, origin: nil))
        }
        let author = normalizedAuthor(author)
        for result in results {
            guard result.name == name, normalizedAuthor(result.author ?? "") == author,
                  let cover = result.coverUrl, !cover.isEmpty, seen.insert(cover).inserted else { continue }
            items.append(CoverCandidate(originName: result.originName ?? result.origin ?? "未知来源", coverUrl: cover, origin: result.origin))
        }
        return items
    }

    private static func normalizedAuthor(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s*(作\s*者|著)\s*[:：]?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
