import Foundation

struct ProtectedHTML {
    let text: String
    private let fragments: [(String, String)]

    init(_ text: String, enabled: Bool) throws {
        guard enabled else { self.text = text; fragments = []; return }
        let regex = try NSRegularExpression(pattern: "<usehtml>.*?</usehtml>", options: .dotMatchesLineSeparators)
        let original = text as NSString
        let prefix = "legado_usehtml_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "_"
        var masked = text
        var fragments: [(String, String)] = []
        for (index, match) in regex.matches(in: text, range: NSRange(location: 0, length: original.length)).enumerated().reversed() {
            let placeholder = prefix + String(index)
            fragments.append((placeholder, original.substring(with: match.range)))
            masked = (masked as NSString).replacingCharacters(in: match.range, with: placeholder)
        }
        self.text = masked
        self.fragments = fragments
    }

    func restore(_ text: String) -> String {
        fragments.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}
