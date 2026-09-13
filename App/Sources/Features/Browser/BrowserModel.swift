import Foundation
import Observation

@Observable
final class BrowserModel {
    var verificationCode = ""
    var errorMessage: String?
    var isCompleting = false
    var submittedCode: String? {
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }
}

enum WebViewResourceMatcher {
    static func matches(_ value: String, pattern: String?) -> Bool {
        guard let pattern, !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: "\\A(?:\(pattern))\\z") else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range)?.range == range
    }
}
