import Foundation
import CoreText
import CoreGraphics

enum ReaderPunctuation {
    static let offsetKey = NSAttributedString.Key("LegadoPunctuationOffset")
    static let trimKey = NSAttributedString.Key("LegadoPunctuationTrim")
    private static let opening = Set("\u{201c}\u{2018}\u{ff08}\u{3014}\u{ff3b}\u{ff5b}\u{3008}\u{300a}\u{300c}\u{300e}\u{3010}\u{3016}\u{301d}\u{fe41}\u{fe43}".utf16)
    private static let closing = Set("\u{201d}\u{2019}\u{ff09}\u{3015}\u{ff3d}\u{ff5d}\u{3009}\u{300b}\u{300d}\u{300f}\u{3011}\u{3017}\u{301e}\u{fe42}\u{fe44}\u{3002}\u{ff0c}\u{3001}\u{ff1b}\u{ff1a}\u{ff01}\u{ff1f}\u{ff0e}".utf16)

    static func trim(width: CGFloat, em: CGFloat, left: CGFloat, right: CGFloat) -> (width: CGFloat, offset: CGFloat) {
        guard width >= em * 0.9 else { return (0, 0) }
        let rightOnly = right >= left * 2
        let leftOnly = !rightOnly && left >= right * 2
        let available = rightOnly ? right : leftOnly ? left : 2 * min(left, right)
        let amount = min(width / 2, max(0, available))
        guard amount > 0.5 else { return (0, 0) }
        return (amount, rightOnly ? 0 : leftOnly ? -amount : -amount / 2)
    }

    static func targets(_ string: String, mode: String) -> [Int] {
        guard ["all", "adjacent", "adjacentLineEnd"].contains(mode) else { return [] }
        let raw = string as NSString
        var classes = [Int: Int]()
        raw.enumerateSubstrings(in: NSRange(location: 0, length: raw.length), options: .byComposedCharacterSequences) { _, range, _, _ in
            guard range.length == 1 else { return }
            let value = raw.character(at: range.location)
            classes[range.location] = opening.contains(value) ? 1 : closing.contains(value) ? 2 : 0
        }
        return classes.keys.sorted().filter { index in
            let kind = classes[index] ?? 0
            if mode == "all" { return kind != 0 }
            return kind == 2 ? (classes[index + 1] ?? 0) != 0
                : kind == 1 && (classes[index - 1] == 2 || classes[index + 1] == 1)
        }
    }

    static func apply(to text: NSMutableAttributedString, indices: [Int]) {
        for index in indices where index >= 0 && index < text.length {
            guard text.attribute(trimKey, at: index, effectiveRange: nil) == nil else { continue }
            let range = NSRange(location: index, length: 1)
            var attributes = text.attributes(at: index, effectiveRange: nil)
            let tracking = (attributes[.init(kCTKernAttributeName as String)] as? NSNumber)?.doubleValue ?? 0
            attributes.removeValue(forKey: .init(kCTKernAttributeName as String))
            let glyph = CTLineCreateWithAttributedString(NSAttributedString(string: (text.string as NSString).substring(with: range), attributes: attributes))
            let width = CGFloat(CTLineGetTypographicBounds(glyph, nil, nil, nil))
            let bounds = CTLineGetBoundsWithOptions(glyph, .useGlyphPathBounds)
            let em = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{6211}", attributes: attributes))
            let result = trim(width: width, em: CGFloat(CTLineGetTypographicBounds(em, nil, nil, nil)),
                              left: max(0, bounds.minX), right: max(0, width - bounds.maxX))
            guard result.width > 0 else { continue }
            text.addAttributes([.init(kCTKernAttributeName as String): tracking - result.width,
                                offsetKey: result.offset, trimKey: result.width], range: range)
        }
    }

    static func lineEnd(in text: NSAttributedString, range: CFRange) -> Int? {
        let raw = text.string as NSString
        let end = min(raw.length, range.location + range.length)
        guard end < raw.length, range.length > 0 else { return nil }
        var index = end - 1
        while index >= range.location {
            let cluster = raw.rangeOfComposedCharacterSequence(at: index)
            let value = raw.substring(with: cluster)
            if value.contains("\n") || value.contains("\r") { return nil }
            if !value.trimmingCharacters(in: .whitespaces).isEmpty {
                return cluster.length == 1 && closing.contains(raw.character(at: index)) ? index : nil
            }
            index = cluster.location - 1
        }
        return nil
    }
}
