import Foundation
import JavaScriptCore
import CryptoKit

final class TxtTitleProcessor {
    static let ruleSeparator = "\u{1fac5}\u{1f233}\u{1f3fb}"
    private let book: Book
    private var lastVolumeTitle = ""

    init(book: Book) { self.book = book }

    func select(content: String, rules: [TxtTocRule]) throws -> TxtTocRule? {
        var maximum = -1
        var selected: TxtTocRule?
        for rule in rules.filter({ $0.enable && !$0.rule.isEmpty }).sorted(by: { $0.serialNumber < $1.serialNumber }) {
            try Task.checkCancellation()
            guard let regex = try? NSRegularExpression(pattern: rule.rule, options: .anchorsMatchLines) else { continue }
            var start = 0, count = 0, errors = 0
            var lastTitle: String?
            let text = content as NSString
            for match in regex.matches(in: content, range: NSRange(location: 0, length: text.length)) {
                let length = match.range.location - start
                if start == 0 || length > 1000 {
                    let title = try replace(text.substring(with: match.range), script: rule.replacement,
                        index: count + 1, previousTitle: lastTitle, previousLength: length).title
                    if !title.isEmpty { lastTitle = title; count += 1 }
                    start = NSMaxRange(match.range)
                } else if length < 100 { errors += 1 }
            }
            if count >= errors * 3 && count > maximum + 2 {
                maximum = count; selected = rule
                if maximum > 70 { break }
            }
        }
        return selected
    }

    func replace(_ title: String, script: String, index: Int, previousTitle: String?, previousLength: Int) throws -> (title: String, volumes: [String]) {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (title, []) }
        let engine = JsEngine()
        var volumes: [String] = []
        let putVolume: @convention(block) (String) -> Void = { [self] value in
            lastVolumeTitle = value
            volumes.append(value)
        }
        engine.libraryInitializer = { context in
            context.objectForKeyedSubscript("java")?.setObject(putVolume, forKeyedSubscript: "putVolume" as NSString)
        }
        let binding = try JSONSerialization.jsonObject(with: JSONEncoder().encode(book))
        let result = try engine.evaluateScript(script, bindings: ["result": title, "book": binding, "index": index,
            "prevTitle": previousTitle as Any? ?? NSNull(), "prevLength": previousLength, "lastVolumeTitle": lastVolumeTitle])
        return (result.map { String(describing: $0) } ?? "null", volumes)
    }

    func setVolumeTitle(_ title: String) { lastVolumeTitle = title }

    static func chapterURL(originName: String, index: Int, title: String) -> String {
        let hash = Insecure.MD5.hash(data: Data((originName + String(index) + title).utf8)).map { String(format: "%02x", $0) }.joined()
        return String(hash.dropFirst(8).prefix(16))
    }
}
