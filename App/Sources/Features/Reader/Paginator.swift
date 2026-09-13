import Foundation
import CoreText
import CoreGraphics

struct ReaderPage {
    /// 章节排版文本中的 UTF-16 范围，包含标题与段落分隔符。
    let range: NSRange
    let text: NSAttributedString
    let frame: CTFrame?
}

struct ReaderPagination {
    let text: NSAttributedString
    let pages: [ReaderPage]
    let contentSize: CGSize

    func pageIndex(at characterOffset: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        let offset = max(0, min(characterOffset, max(0, text.length - 1)))
        return pages.lastIndex(where: { $0.range.location <= offset }) ?? 0
    }

    func firstCharacterOffset(on page: Int) -> Int {
        guard !pages.isEmpty else { return 0 }
        return pages[min(max(0, page), pages.count - 1)].range.location
    }
}

enum PaginationError: Error { case invalidPageSize, noVisibleCharacters }

struct Paginator {
    var fontName = "PingFangSC-Regular"

    func paginate(title: String, paragraphs: [String], size: CGSize,
                  settings: ReaderSettings) throws -> ReaderPagination {
        let settings = settings.normalized
        let contentSize = CGSize(width: size.width - settings.paddingLeft - settings.paddingRight,
                                 height: size.height - settings.paddingTop - settings.paddingBottom)
        guard contentSize.width.isFinite, contentSize.height.isFinite,
              contentSize.width > 0, contentSize.height > 0 else { throw PaginationError.invalidPageSize }
        let body = paragraphs.joined(separator: "\n")
        let string = title.isEmpty ? body : title + (body.isEmpty ? "" : "\n" + body)
        let font = CTFontCreateWithName(fontName as CFString, settings.textSize, nil)
        func paragraphStyle(indent: CGFloat, multiplier: CGFloat) -> CTParagraphStyle {
            var indent = indent
            var multiplier = multiplier
            var spacing = CGFloat(settings.paragraphSpacing)
            return withUnsafePointer(to: &indent) { indentPointer in
                withUnsafePointer(to: &multiplier) { multiplierPointer in
                    withUnsafePointer(to: &spacing) { spacingPointer in
                        let values = [
                            CTParagraphStyleSetting(spec: .firstLineHeadIndent, valueSize: MemoryLayout<CGFloat>.size, value: indentPointer),
                            CTParagraphStyleSetting(spec: .lineHeightMultiple, valueSize: MemoryLayout<CGFloat>.size, value: multiplierPointer),
                            CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: spacingPointer)
                        ]
                        return CTParagraphStyleCreate(values, values.count)
                    }
                }
            }
        }
        let color: CGColor
        switch settings.theme {
        case .night: color = CGColor(gray: 173 / 255, alpha: 1)
        case .day, .eyeCare: color = CGColor(red: 62 / 255, green: 61 / 255, blue: 59 / 255, alpha: 1)
        }
        let attributed = NSMutableAttributedString(string: string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle(indent: 0, multiplier: settings.lineSpacingMultiplier)
        ])
        if !title.isEmpty {
            attributed.addAttribute(NSAttributedString.Key(kCTParagraphStyleAttributeName as String),
                value: paragraphStyle(indent: 0, multiplier: 1),
                range: NSRange(location: 0, length: (title as NSString).length))
        }
        let text = NSAttributedString(attributedString: attributed)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: CGRect(origin: .zero, size: contentSize), transform: nil)
        var pages: [ReaderPage] = [], offset = 0
        while offset < text.length {
            try Task.checkCancellation()
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { throw PaginationError.noVisibleCharacters }
            let range = NSRange(location: offset, length: visible.length)
            pages.append(ReaderPage(range: range, text: text.attributedSubstring(from: range), frame: frame))
            offset = NSMaxRange(range)
        }
        if pages.isEmpty { pages = [ReaderPage(range: NSRange(location: 0, length: 0), text: text, frame: nil)] }
        return ReaderPagination(text: text, pages: pages, contentSize: contentSize)
    }
}
