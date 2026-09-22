import Foundation
import CoreText
import CoreGraphics
import LegadoCore

struct ReaderPage {
    /// 章节排版文本中的 UTF-16 范围，包含标题与段落分隔符。
    let range: NSRange
    let text: NSAttributedString
    let frame: CTFrame?
    var imageURL: String? = nil
    var images: [ReaderPlacedImage] = []
    var height: CGFloat = 0
    var lines: [CTLine] = []
    var lineOrigins: [CGPoint] = []
}

struct ReaderPagination {
    let text: NSAttributedString
    let pages: [ReaderPage]
    let contentSize: CGSize
    var titleLength: Int = 0

    func characterOffset(at point: CGPoint, on pageIndex: Int) -> Int? {
        guard pages.indices.contains(pageIndex) else { return nil }
        let page = pages[pageIndex]
        if let image = page.images.first(where: { $0.rect.contains(point) }) { return image.offset }
        let y = contentSize.height - point.y
        for (index, line) in page.lines.enumerated() {
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let origin = page.lineOrigins[index]
            guard y >= origin.y - descent, y <= origin.y + ascent,
                  point.x >= origin.x, point.x <= origin.x + width else { continue }
            let offset = CTLineGetStringIndexForPosition(line, CGPoint(x: point.x - origin.x, y: y - origin.y))
            return offset == kCFNotFound ? nil : offset
        }
        return nil
    }

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
                  settings: ReaderSettings, imageBaseURL: String? = nil, isVolume: Bool = false, highlightRules: [HighlightRule] = [], book: Book = Book(),
                  imageStyle: String = "SINGLE", imageSizes: [String: CGSize] = [:], imageSize: (String) throws -> CGSize? = { _ in nil }) throws -> ReaderPagination {
        let settings = settings.normalized
        let visibleTitle = settings.titleMode == 2 && !isVolume && !paragraphs.isEmpty ? "" : title
        let split = ReaderTypography.splitTitle(visibleTitle, enabled: settings.configuration.splitChapterTitle && !isVolume)
        let title = split.map { $0.0 + "\n" + $0.1 } ?? visibleTitle
        let contentSize = CGSize(width: size.width - settings.paddingLeft - settings.paddingRight,
                                 height: size.height - settings.paddingTop - settings.paddingBottom)
        guard contentSize.width.isFinite, contentSize.height.isFinite,
              contentSize.width > 0, contentSize.height > 0 else { throw PaginationError.invalidPageSize }
        let body = paragraphs.joined(separator: "\n")
        let rawString = title.isEmpty ? body : title + (body.isEmpty ? "" : "\n" + body)
        let imagePattern = try NSRegularExpression(pattern: #"<img\b[^>]*\bsrc\s*=\s*(?:"([^"]*(?:"[^>]+\})?)"|'([^']+)'|([^\s>]+))[^>]*>"#, options: .caseInsensitive)
        let raw = rawString as NSString
        let matches = imagePattern.matches(in: rawString, range: NSRange(location: 0, length: raw.length))
        var string = "", images: [ReaderImageSpec] = [], start = 0
        for match in matches {
            let prefix = raw.substring(with: NSRange(location: start, length: match.range.location - start))
            if !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { string += prefix }
            let source = (1...3).first { match.range(at: $0).location != NSNotFound }!
            var url = raw.substring(with: match.range(at: source)).replacingOccurrences(of: "&amp;", with: "&")
            if let imageBaseURL {
                let address = CustomUrl(url).getUrl()
                let suffix = String(url.dropFirst(address.count))
                url = (URL(string: address, relativeTo: URL(string: imageBaseURL))?.absoluteURL.absoluteString ?? address) + suffix
            }
            let natural = try imageSizes[url] ?? imageSize(url)
            images.append(try ReaderImageLayout.spec(offset: (string as NSString).length, url: url, style: imageStyle,
                natural: natural, available: contentSize, textSize: settings.textSize,
                scroll: (settings.isEInk ? settings.configuration.pageAnimEInk : settings.pageAnim) == 3 || !settings.isEInk && settings.pageAnim == 4 && settings.noAnimScrollPage))
            // Android 单图排版用一个空格占据章节字符坐标。
            string += " "
            start = NSMaxRange(match.range)
        }
        let suffix = raw.substring(from: start)
        if matches.isEmpty || !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { string += suffix }
        let fontName = settings.textFont.isEmpty ? fontName : settings.textFont
        let attributed = NSMutableAttributedString(string: string, attributes: ReaderTypography.bodyAttributes(settings, fontName: fontName))
        if !title.isEmpty {
            attributed.addAttributes(ReaderTypography.titleAttributes(settings, bodyFontName: fontName),
                range: NSRange(location: 0, length: (title as NSString).length))
        }
        if let split {
            var numberSettings = settings
            numberSettings.configuration.titleSize = settings.configuration.titleNumberSize
            if settings.configuration.titleNumberColor != 0 { numberSettings.configuration.titleColor = settings.configuration.titleNumberColor }
            numberSettings.configuration.titleBottomSpacing = settings.configuration.titleNumberSpacing
            attributed.addAttributes(ReaderTypography.titleAttributes(numberSettings, bodyFontName: fontName, numberTitle: true),
                                     range: NSRange(location: 0, length: (split.0 as NSString).length + 1))
        }
        let titleLength = title.isEmpty ? 0 : (title as NSString).length + (body.isEmpty ? 0 : 1)
        try ReaderRuleHighlight.apply(to: attributed, titleLength: titleLength, rules: highlightRules, book: book)
        ReaderPunctuation.apply(to: attributed, indices: ReaderPunctuation.targets(attributed.string, mode: settings.punctuationCompress).filter { $0 >= titleLength })
        for image in images where image.style == "TEXT" {
            if let delegate = ReaderImageLayout.delegate(size: image.size) {
                attributed.addAttributes([.init(kCTRunDelegateAttributeName as String): delegate, ReaderImageLayout.imageKey: image.url],
                    range: NSRange(location: image.offset, length: 1))
            }
        }
        let text = NSAttributedString(attributedString: attributed)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: CGRect(origin: .zero, size: contentSize), transform: nil)
        var pages: [ReaderPage] = [], offset = 0, pageStart = 0
        var pageLines: [CTLine] = [], pageOrigins: [CGPoint] = [], pageImages: [ReaderPlacedImage] = []
        var pageFrame: CTFrame?, usedHeight: CGFloat = 0
        func finishPage() {
            guard offset > pageStart else { return }
            let range = NSRange(location: pageStart, length: offset - pageStart)
            pages.append(ReaderPage(range: range, text: text.attributedSubstring(from: range), frame: pageFrame,
                imageURL: pageImages.count == 1 && pageLines.isEmpty ? pageImages[0].url : nil,
                images: pageImages, height: max(contentSize.height, usedHeight), lines: pageLines, lineOrigins: pageOrigins))
            pageStart = offset; pageFrame = nil; usedHeight = 0
            pageLines = []; pageOrigins = []; pageImages = []
        }
        while offset < text.length {
            try Task.checkCancellation()
            if let image = images.first(where: { $0.offset == offset && $0.style != "TEXT" }) {
                if image.style == "SINGLE" || usedHeight + image.size.height > contentSize.height { finishPage() }
                let x = image.style == "LEFT" ? 0 : image.style == "RIGHT" ? contentSize.width - image.size.width : (contentSize.width - image.size.width) / 2
                let y = image.style == "SINGLE" ? (contentSize.height - image.size.height) / 2 : usedHeight
                pageImages.append(ReaderPlacedImage(offset: offset, url: image.url, click: image.click,
                    rect: CGRect(origin: CGPoint(x: x, y: y), size: image.size)))
                usedHeight += image.size.height; offset += 1
                if image.style == "SINGLE" || usedHeight >= contentSize.height { finishPage() }
                continue
            }
            let boundary = images.first(where: { $0.offset > offset && $0.style != "TEXT" })?.offset ?? text.length
            // CoreText 不为首个段落应用 paragraphSpacingBefore，首页单独保留标题上边距。
            let availableHeight = contentSize.height - usedHeight - (offset == 0 && !title.isEmpty ? settings.titleTopSpacing : 0)
            let pagePath = availableHeight == contentSize.height ? path : CGPath(rect: CGRect(x: 0, y: 0,
                width: contentSize.width, height: max(1, availableHeight)), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: boundary - offset), pagePath, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else {
                if offset > pageStart { finishPage(); continue }
                throw PaginationError.noVisibleCharacters
            }
            let range = NSRange(location: offset, length: visible.length)
            var lines = CTFrameGetLines(frame) as! [CTLine]
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
            if ["lineEnd", "adjacentLineEnd"].contains(settings.punctuationCompress) {
                let compressed = NSMutableAttributedString(attributedString: text)
                for (index, line) in lines.enumerated() {
                    let lineRange = CTLineGetStringRange(line)
                    guard lineRange.location >= titleLength, let target = ReaderPunctuation.lineEnd(in: text, range: lineRange),
                          text.attribute(ReaderPunctuation.trimKey, at: target, effectiveRange: nil) == nil else { continue }
                    ReaderPunctuation.apply(to: compressed, indices: [target])
                    let typesetter = CTTypesetterCreateWithAttributedString(compressed)
                    let replacement = CTTypesetterCreateLine(typesetter, lineRange)
                    let isTitle = !title.isEmpty && lineRange.location < (title as NSString).length
                    lines[index] = settings.textFullJustify && !isTitle
                        ? CTLineCreateJustifiedLine(replacement, 1, contentSize.width) ?? replacement : replacement
                }
            }
            if settings.textBottomJustify, NSMaxRange(range) < boundary, lines.count > 1 {
                var descent: CGFloat = 0
                _ = CTLineGetTypographicBounds(lines.last!, nil, &descent, nil)
                let remaining = max(0, origins.last!.y - descent)
                for index in origins.indices {
                    origins[index].y -= remaining * CGFloat(index) / CGFloat(origins.count - 1)
                }
            }
            for image in images where image.style == "TEXT" && NSLocationInRange(image.offset, range) {
                if let index = lines.firstIndex(where: { line in
                    let current = CTLineGetStringRange(line)
                    return image.offset >= current.location && image.offset < current.location + current.length
                }) {
                    let x = origins[index].x + CTLineGetOffsetForStringIndex(lines[index], image.offset, nil)
                    pageImages.append(ReaderPlacedImage(offset: image.offset, url: image.url, click: image.click,
                        rect: CGRect(x: x, y: contentSize.height - origins[index].y - image.size.height,
                            width: image.size.width, height: image.size.height)))
                }
            }
            pageFrame = frame; pageLines += lines; pageOrigins += origins
            if let line = lines.last, let origin = origins.last {
                var descent: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, nil, &descent, nil)
                usedHeight = max(usedHeight, contentSize.height - origin.y + descent)
            }
            offset = NSMaxRange(range)
            if offset < boundary { finishPage() }
        }
        finishPage()
        if pages.isEmpty { pages = [ReaderPage(range: NSRange(location: 0, length: 0), text: text, frame: nil)] }
        return ReaderPagination(text: text, pages: pages, contentSize: contentSize, titleLength: titleLength)
    }
}
