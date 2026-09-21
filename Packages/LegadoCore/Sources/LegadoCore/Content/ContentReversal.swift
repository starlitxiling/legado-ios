import Foundation
import CryptoKit

public enum ContentReversal {
    private static let markup = #"<usehtml>.*?</usehtml>|<img[^>]*src="([^"]*(?:"[^>]+\})?)"[^>]*>|\[newpage\]|<!--[\s\S]*?-->|</?[a-zA-Z](?:[^<>"']|"[^"]*"|'[^']*')*>|&(?:#\d+|#x[\da-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);"#
    private static let mirrors: [Unicode.Scalar: Unicode.Scalar] = {
        let pairs = Array(("\u{201c}\u{201d}\u{2018}\u{2019}\u{3010}\u{3011}()<>{}[]\u{ff08}\u{ff09}\u{300a}\u{300b}\u{3008}\u{3009}\u{3016}\u{3017}\u{3014}\u{3015}\u{300e}\u{300f}\u{300c}\u{300d}\u{ff5b}\u{ff5d}\u{2264}\u{2265}\u{2266}\u{2267}\u{2286}\u{2287}\u{2282}\u{2283}\u{25e2}\u{25e3}\u{25e4}\u{25e5}\u{2190}\u{2192}\u{2196}\u{2197}\u{2199}\u{2198}\u{261c}\u{261e}\u{a9c1}\u{a9c2}\u{256d}\u{256e}\u{2570}\u{256f}\u{ab}\u{bb}\u{301d}\u{301e}\u{ff1c}\u{ff1e}\u{ff3b}\u{ff3d}\u{ff62}\u{ff63}").unicodeScalars)
        var result: [Unicode.Scalar: Unicode.Scalar] = [:]
        for index in stride(from: 0, to: pairs.count, by: 2) { result[pairs[index]] = pairs[index + 1]; result[pairs[index + 1]] = pairs[index] }
        return result
    }()

    public static func reverse(_ content: String) throws -> String {
        let regex = try NSRegularExpression(pattern: markup, options: [.dotMatchesLineSeparators])
        let text = content as NSString
        let range = NSRange(location: 0, length: text.length)
        let rich = regex.firstMatch(in: content, range: range) != nil
        let boundaries = rich ? try NSRegularExpression(pattern: markup + #"|\r\n|\r|\n"#, options: [.dotMatchesLineSeparators]).matches(in: content, range: range) : []
        func reverseSegment(_ range: NSRange) -> String {
            let scalars = Array(text.substring(with: range).unicodeScalars)
            var first = 0, last = scalars.count
            if rich && (range.location == 0 || text.character(at: range.location - 1) == 10 || text.character(at: range.location - 1) == 13) {
                while first < last && CharacterSet.whitespacesAndNewlines.contains(scalars[first]) { first += 1 }
                while last > first && CharacterSet.whitespacesAndNewlines.contains(scalars[last - 1]) { last -= 1 }
            }
            return String(String.UnicodeScalarView(Array(scalars[..<first]) + scalars[first..<last].reversed().map { mirrors[$0] ?? $0 } + Array(scalars[last...])))
        }
        var result = "", start = 0
        for boundary in boundaries {
            try Task.checkCancellation()
            result += reverseSegment(NSRange(location: start, length: boundary.range.location - start))
            result += text.substring(with: boundary.range)
            start = NSMaxRange(boundary.range)
        }
        result += reverseSegment(NSRange(location: start, length: text.length - start))
        return result
    }
}

extension BookHelp {
    public static func reverseContent(directory: URL, book: Book, chapter: BookChapter) throws -> String? {
        guard let original = try content(directory: directory, book: book, chapter: chapter), !original.isEmpty else { return nil }
        let file = contentURL(directory: directory, book: book, chapter: chapter)
        let marker = file.appendingPathExtension("reversed")
        func fingerprint(_ content: String) -> String { Insecure.MD5.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined() }
        var restored: String?
        if FileManager.default.fileExists(atPath: marker.path) {
            let saved = try String(contentsOf: marker, encoding: .utf8)
            if let newline = saved.firstIndex(of: "\n"), saved[..<newline] == fingerprint(original) { restored = String(saved[saved.index(after: newline)...]) }
        }
        let changed = try restored ?? ContentReversal.reverse(original)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if restored == nil { try Data((fingerprint(changed) + "\n" + original).utf8).write(to: marker, options: .atomic) }
        do { try save(changed, directory: directory, book: book, chapter: chapter) }
        catch {
            if restored == nil {
                do { try FileManager.default.removeItem(at: marker) }
                catch { NSLog("Unable to remove failed content reversal marker: %@", error.localizedDescription) }
            }
            throw error
        }
        if restored != nil { try FileManager.default.removeItem(at: marker) }
        return changed
    }
}
