import Foundation
import CoreText
import CoreGraphics

struct ReaderPage {
    /// 章节排版文本中的 UTF-16 范围，包含标题与段落分隔符。
    let range: NSRange
    let text: NSAttributedString
    let frame: CTFrame?
    var imageURL: String? = nil
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
                  settings: ReaderSettings, imageBaseURL: String? = nil) throws -> ReaderPagination {
        let settings = settings.normalized
        let contentSize = CGSize(width: size.width - settings.paddingLeft - settings.paddingRight,
                                 height: size.height - settings.paddingTop - settings.paddingBottom)
        guard contentSize.width.isFinite, contentSize.height.isFinite,
              contentSize.width > 0, contentSize.height > 0 else { throw PaginationError.invalidPageSize }
        let body = paragraphs.joined(separator: "\n")
        let rawString = title.isEmpty ? body : title + (body.isEmpty ? "" : "\n" + body)
        let imagePattern = try NSRegularExpression(pattern: #"<img\b[^>]*\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>"#, options: .caseInsensitive)
        let raw = rawString as NSString
        let matches = imagePattern.matches(in: rawString, range: NSRange(location: 0, length: raw.length))
        var string = "", images: [(offset: Int, url: String)] = [], start = 0
        for match in matches {
            let prefix = raw.substring(with: NSRange(location: start, length: match.range.location - start))
            if !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { string += prefix }
            let source = (1...3).first { match.range(at: $0).location != NSNotFound }!
            var url = raw.substring(with: match.range(at: source)).replacingOccurrences(of: "&amp;", with: "&")
            if let imageBaseURL {
                url = URL(string: url, relativeTo: URL(string: imageBaseURL))?.absoluteURL.absoluteString ?? url
            }
            images.append((offset: (string as NSString).length, url: url))
            // Android 单图排版用一个空格占据章节字符坐标。
            string += " "
            start = NSMaxRange(match.range)
        }
        let suffix = raw.substring(from: start)
        if matches.isEmpty || !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { string += suffix }
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
            if let image = images.first(where: { $0.offset == offset }) {
                let range = NSRange(location: offset, length: 1)
                pages.append(ReaderPage(range: range, text: text.attributedSubstring(from: range), frame: nil, imageURL: image.url))
                offset += 1
                continue
            }
            let boundary = images.first(where: { $0.offset > offset })?.offset ?? text.length
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: boundary - offset), path, nil)
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
