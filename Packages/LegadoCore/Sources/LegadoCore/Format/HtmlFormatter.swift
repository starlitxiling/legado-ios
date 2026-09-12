import Foundation

public enum HtmlFormatter {
    // JVM 默认的 \s、\d 是 ASCII；ICU 默认使用 Unicode 字符类。
    private static let nbsp = regex("(&nbsp;)+")
    private static let esp = regex("(&ensp;|&emsp;)")
    private static let noPrint = regex("(&thinsp;|&zwnj;|&zwj;|\u{2009}|\u{200c}|\u{200d})")
    private static let wrapHTML = regex(#"</?(?:div|p|br|hr|h[0-9]|article|dd|dl)[^>]*>"#)
    private static let comment = regex("<!--[^>]*-->")
    private static let notImageHTML = regex("</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>")
    private static let otherHTML = regex("</?[a-zA-Z]+(?=[ >])[^<>]*>")
    private static let indent1 = regex(#"[ \t\n\x{0B}\f\r]*\n+[ \t\n\x{0B}\f\r]*"#)
    private static let indent2 = regex(#"^[\n \t\x{0B}\f\r]+"#)
    private static let last = regex(#"[\n \t\x{0B}\f\r]+$"#)
    private static let image = regex(asciiImagePattern(
        #"<img[^>]*\ssrc\s*=\s*['"]([^'"{>]*\{(?:[^{}]|\{[^}>]+\})+\})['"][^>]*>|<img[^>]*\sdata-(?:src|original|srcset)\s*=\s*['"]([^'">]+)['"][^>]*>|<img[^>]*\ssrc\s*=\s*"([^">]+)"[^>]*>|<img[^>]*\s(?:data-[^=>]*|src)=\s*['"]([^'">]*)['"][^>]*>"#
            .replacingOccurrences(of: #"\s"#, with: #"[ \t\n\x{0B}\f\r]"#)))
    private static let parameter = regex(#"[ \t\n\x{0B}\f\r]*,[ \t\n\x{0B}\f\r]*(?=\{)"#)
    // Java 的点号排除这些行终止符，但允许 VT 和 FF。
    private static let dataURI = regex(#"\Adata:[^\n\r\x{85}\x{2028}\x{2029}]*?;base64,([^\n\r\x{85}\x{2028}\x{2029}]*)\z"#)
    private static let scheme = regex(#"\A[A-Za-z][A-Za-z0-9+.-]*:"#)

    public static func format(_ html: String?, otherRegex: NSRegularExpression? = nil) -> String {
        formatText(html, otherRegex: otherRegex ?? otherHTML, paragraphIndent: "　　")
    }

    public static func formatIntro(_ html: String?) -> String {
        formatText(html, otherRegex: otherHTML, paragraphIndent: "")
    }

    private static func formatText(_ html: String?, otherRegex: NSRegularExpression, paragraphIndent: String) -> String {
        guard let html else { return "" }
        var text = html.replacingOccurrences(of: #"\r\n"#, with: "\n")
            .replacingOccurrences(of: #"\n"#, with: "\n")
            .replacingOccurrences(of: #"\r"#, with: "\n")
        for (pattern, replacement) in [(nbsp, " "), (esp, " "), (noPrint, ""), (wrapHTML, "\n"),
                                       (comment, ""), (otherRegex, ""), (indent1, "\n" + paragraphIndent),
                                       (indent2, paragraphIndent), (last, "")] {
            text = pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                     withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
        }
        return text
    }

    public static func formatKeepImg(_ html: String?, redirectUrl: URL? = nil) -> String {
        guard let html else { return "" }
        let text = format(html, otherRegex: notImageHTML)
        let source = text as NSString
        var result = ""
        var position = 0
        for match in image.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: position, length: match.range.location - position))
            let group = (1...4).first { match.range(at: $0).location != NSNotFound }!
            var path = source.substring(with: match.range(at: group))
            var suffix = ""
            if group == 1, let separator = parameter.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) {
                let value = path as NSString
                suffix = "," + value.substring(from: NSMaxRange(separator.range))
                path = value.substring(to: separator.range.location)
            }
            result += "<img src=\"" + absoluteURL(path, base: redirectUrl) + suffix + "\">"
            position = NSMaxRange(match.range)
        }
        result += source.substring(from: position)
        return result
    }

    private static func absoluteURL(_ path: String, base: URL?) -> String {
        // Kotlin trim 使用 Character.isWhitespace || isSpaceChar，不包含 U+0085。
        let whitespace = CharacterSet(charactersIn: "\u{0009}\u{000a}\u{000b}\u{000c}\u{000d}\u{001c}\u{001d}\u{001e}\u{001f} \u{00a0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200a}\u{2028}\u{2029}\u{202f}\u{205f}\u{3000}")
        let trimmed = path.trimmingCharacters(in: whitespace)
        guard let base else { return trimmed }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") { return trimmed }
        if dataURI.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil { return trimmed }
        if trimmed.hasPrefix("javascript") { return "" }
        // java.net.URL 只剥离两端 ASCII 控制字符；仅查询串以当前目录为基址。
        let relative = path.trimmingCharacters(in: CharacterSet(charactersIn: "\u{0000}"..." "))
        if scheme.firstMatch(in: relative, range: NSRange(relative.startIndex..., in: relative)) != nil { return trimmed }
        let context = Address(base.absoluteString)
        var address = Address(relative)
        address.scheme = context.scheme
        if address.authority != nil { return address.text }
        address.authority = context.authority
        if address.path.isEmpty {
            if address.query != nil {
                address.path = directory(context.path)
            } else {
                address.path = context.path
                address.query = context.query
                if address.fragment == nil { address.fragment = context.fragment }
            }
        } else if !address.path.hasPrefix("/") {
            address.path = normalizePath(directory(context.path) + address.path)
        }
        return address.text
    }

    private struct Address {
        var scheme = ""
        var authority: String?
        var path: String
        var query: String?
        var fragment: String?

        init(_ text: String) {
            var remainder = text
            if let index = remainder.firstIndex(of: "#") {
                fragment = String(remainder[index...])
                remainder = String(remainder[..<index])
            }
            if let index = remainder.firstIndex(of: "?") {
                query = String(remainder[index...])
                remainder = String(remainder[..<index])
            }
            if let match = HtmlFormatter.scheme.firstMatch(in: remainder, range: NSRange(remainder.startIndex..., in: remainder)),
               let range = Range(match.range, in: remainder) {
                scheme = String(remainder[range])
                remainder = String(remainder[range.upperBound...])
            }
            if remainder.hasPrefix("//") && !remainder.hasPrefix("////") {
                remainder.removeFirst(2)
                let end = remainder.firstIndex(of: "/") ?? remainder.endIndex
                authority = String(remainder[..<end])
                remainder = String(remainder[end...])
            }
            path = remainder
        }

        var text: String {
            scheme + (authority.map { "//" + $0 } ?? "") + path + (query ?? "") + (fragment ?? "")
        }
    }

    private static func directory(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "/" }
        return String(path[...slash])
    }

    private static func normalizePath(_ path: String) -> String {
        var segments: [String] = []
        let parts = path.components(separatedBy: "/")
        for (index, part) in parts.enumerated() {
            if part == "." {
                if index == parts.count - 1 { segments.append("") }
            } else if part == "..", segments.count > 1, segments.last != ".." {
                segments.removeLast()
                if index == parts.count - 1 { segments.append("") }
            } else {
                segments.append(part)
            }
        }
        return segments.joined(separator: "/")
    }

    private static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static func asciiImagePattern(_ pattern: String) -> String {
        // Pattern.CASE_INSENSITIVE 未启用 UNICODE_CASE；ICU 的忽略大小写会额外匹配 ſ 等字符。
        ["img", "srcset", "src", "data", "original"].reduce(pattern) { result, word in
            result.replacingOccurrences(of: word, with: word.map { "[\($0)\(String($0).uppercased())]" }.joined())
        }
    }
}
