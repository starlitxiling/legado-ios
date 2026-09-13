import Foundation

enum PublicSuffixDomain {
    static func effectiveTldPlusOne(_ domain: String) -> String? {
        let labels = domain.lowercased().split(separator: ".").map(String.init)
        guard !labels.isEmpty else { return nil }
        var suffixCount = 1
        for index in labels.indices {
            let suffix = labels[index...].joined(separator: ".")
            if PublicSuffixTable.exception.contains(suffix) { return suffix }
            if PublicSuffixTable.exact.contains(suffix) { suffixCount = max(suffixCount, labels.count - index) }
            if index > 0 && PublicSuffixTable.wildcard.contains(suffix) {
                suffixCount = max(suffixCount, labels.count - index + 1)
            }
        }
        guard labels.count > suffixCount else { return nil }
        return labels.suffix(suffixCount + 1).joined(separator: ".")
    }
}
