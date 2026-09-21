import Foundation
import CoreText
import CoreGraphics
import LegadoCore

enum ReaderRuleHighlight {
    static let styleKey = NSAttributedString.Key("LegadoHighlightStyle")

    static func apply(to text: NSMutableAttributedString, titleLength: Int, rules: [HighlightRule], book: Book) throws {
        let result = HighlightRuleMatcher.match(text: text.string, titleLength: titleLength, rules: rules, book: book)
        try Task.checkCancellation()
        for match in result.matches {
            let style = HighlightStyle(json: match.style)
            var ranges: [(NSRange, [NSAttributedString.Key: Any])] = []
            text.enumerateAttributes(in: match.range) { values, range, _ in ranges.append((range, values)) }
            for (range, values) in ranges {
                let merged = (values[styleKey] as? HighlightStyle ?? HighlightStyle()).merging(style)
                var attributes: [NSAttributedString.Key: Any] = [styleKey: merged]
                if merged.textColor != 0 { attributes[.init(kCTForegroundColorAttributeName as String)] = color(merged.textColor) }
                let original = values[.init(kCTFontAttributeName as String)] as! CTFont
                let size = merged.fontSize ?? CTFontGetSize(original)
                var font = merged.fontPath.isEmpty ? CTFontCreateCopyWithAttributes(original, size, nil, nil)
                    : CTFontCreateWithName(merged.fontPath as CFString, size, nil)
                var traits = CTFontGetSymbolicTraits(font)
                if merged.bold { traits.insert(.boldTrait) }
                if merged.italic { traits.insert(.italicTrait) }
                font = CTFontCreateCopyWithSymbolicTraits(font, size, nil, traits, traits) ?? font
                attributes[.init(kCTFontAttributeName as String)] = font
                if let spacing = merged.letterSpacing { attributes[.init(kCTKernAttributeName as String)] = size * spacing }
                text.addAttributes(attributes, range: range)
            }
        }
    }

    static func color(_ argb: Int64) -> CGColor {
        let value = ARGBColor(UInt32(truncatingIfNeeded: argb))
        return CGColor(red: value.red, green: value.green, blue: value.blue, alpha: value.opacity)
    }

    static func draw(_ style: HighlightStyle, in rect: CGRect, baseline: CGFloat, foreground: CGColor,
                     context: CGContext, background: Bool) {
        context.saveGState(); defer { context.restoreGState() }
        if background {
            guard style.fill != 0 else { return }
            context.setFillColor(color(style.fill))
            var shape = rect
            switch style.fillShape {
            case "HALF": shape.size.height *= 0.5
            case "BASELINE": shape = CGRect(x: rect.minX, y: baseline - 2, width: rect.width, height: 4)
            case "MARKER": shape = rect.insetBy(dx: -1, dy: rect.height * 0.12)
            case "PILL": shape = rect.insetBy(dx: -rect.height * 0.15 * style.pillPaddingScale, dy: -rect.height * 0.05)
            default: break
            }
            let radius = style.fillShape == "PILL" ? shape.height / 2 : style.fillShape == "ROUNDED" ? 3.0 : 0
            context.addPath(CGPath(roundedRect: shape, cornerWidth: radius, cornerHeight: radius, transform: nil)); context.fillPath()
            return
        }
        func strokeColor(_ value: Int64) { context.setStrokeColor(value == 0 ? foreground : color(value)) }
        func line(_ y: CGFloat) {
            context.move(to: CGPoint(x: rect.minX, y: y)); context.addLine(to: CGPoint(x: rect.maxX, y: y)); context.strokePath()
        }
        if let underline = style.underline, underline.width > 0 {
            strokeColor(underline.color); context.setLineWidth(underline.width)
            let y = baseline - underline.distance - underline.width
            switch underline.kind {
            case "DASHED": context.setLineDash(phase: 0, lengths: [4, 3]); line(y)
            case "DOTTED": context.setLineCap(.round); context.setLineDash(phase: 0, lengths: [0.1, 3]); line(y)
            case "DOUBLE": line(y); line(y - underline.width * 2)
            case "WAVY":
                context.move(to: CGPoint(x: rect.minX, y: y))
                for x in stride(from: rect.minX, through: rect.maxX, by: 1) {
                    context.addLine(to: CGPoint(x: x, y: y + sin((x - rect.minX) * .pi / 3) * 1.5))
                }
                context.strokePath()
            default: line(y)
            }
            context.setLineDash(phase: 0, lengths: []); context.setLineCap(.butt)
        }
        context.setLineWidth(1)
        if let strike = style.strike { strokeColor(strike.color); line(rect.midY) }
        if let box = style.box { strokeColor(box.color); context.stroke(rect) }
    }
}
