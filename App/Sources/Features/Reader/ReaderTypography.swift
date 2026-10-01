import Foundation
import CoreText
import CoreGraphics
import LegadoCore

enum ReaderTypography {
    static func splitTitle(_ title: String, enabled: Bool) -> (String, String)? {
        guard enabled, !title.contains("\n"), !title.contains("\r") else { return nil }
        let number = "[零〇一二三四五六七八九十百千万亿两0-9]+"
        let pattern = "^((?:第\(number)卷[\\s\\p{Zs}]*)?第\(number)[章节回]|番外\(number))[\\s\\p{Zs}]+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(location: 0, length: (title as NSString).length)) else { return nil }
        let first = (title as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        let second = (title as NSString).substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        return second.isEmpty ? nil : (first, second)
    }

    static func color(_ value: String, fallback: UInt32 = 0xFF000000) -> CGColor {
        let color = ARGBColor(hex: value) ?? ARGBColor(fallback)
        return CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.opacity)
    }

    static func bodyColor(_ settings: ReaderSettings) -> CGColor {
        let config = settings.configuration
        return color(settings.isEInk ? config.textColorEInk : settings.theme == .night ? config.textColorNight : config.textColor)
    }

    static func font(_ name: String, size: Double, weight: Double) -> CTFont {
        let original = CTFontCreateWithName(name as CFString, size, nil)
        guard weight != 0 else { return original }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: CTFontCopyFamilyName(original),
            kCTFontTraitsAttribute: [kCTFontWeightTrait: weight]
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    static func bodyAttributes(_ settings: ReaderSettings, fontName: String) -> [NSAttributedString.Key: Any] {
        let bold = settings.configuration.textBold
        return [
            .init(kCTFontAttributeName as String): font(fontName, size: settings.textSize, weight: bold == 1 ? 0.4 : bold == 2 ? -0.4 : 0),
            .init(kCTForegroundColorAttributeName as String): bodyColor(settings),
            .init(kCTKernAttributeName as String): settings.textSize * settings.letterSpacing,
            .init(kCTParagraphStyleAttributeName as String): paragraphStyle(settings: settings, title: false, fontName: fontName)
        ].merging(eInkStroke(settings)) { _, stroke in stroke }
    }

    /// E-readers "darken" text by thickening glyph outlines; a negative CoreText stroke fills and strokes.
    static func eInkStroke(_ settings: ReaderSettings) -> [NSAttributedString.Key: Any] {
        guard settings.isEInk, let width = settings.eInk?.strokeWidth, width != 0 else { return [:] }
        return [.init(kCTStrokeWidthAttributeName as String): width,
                .init(kCTStrokeColorAttributeName as String): bodyColor(settings)]
    }

    static func titleAttributes(_ settings: ReaderSettings, bodyFontName: String, numberTitle: Bool = false) -> [NSAttributedString.Key: Any] {
        let config = settings.configuration
        let weight: Double
        switch config.titleBold {
        case 0: weight = 0
        case 1: weight = 0.4
        case 2: weight = -0.4
        default: weight = config.textBold == 1 ? 0.62 : config.textBold == 2 ? 0 : 0.4
        }
        let color = config.titleColor == 0 || settings.isEInk ? bodyColor(settings) : color(ARGBColor(UInt32(truncatingIfNeeded: config.titleColor)).hex)
        let name = config.titleFont.isEmpty ? bodyFontName : config.titleFont
        let size = max(1, settings.textSize + settings.titleSize)
        return [
            .init(kCTFontAttributeName as String): font(name, size: size, weight: weight),
            .init(kCTForegroundColorAttributeName as String): color,
            .init(kCTKernAttributeName as String): size * settings.letterSpacing,
            .init(kCTParagraphStyleAttributeName as String): paragraphStyle(settings: settings, title: true, fontName: name, numberTitle: numberTitle)
        ].merging(eInkStroke(settings)) { _, stroke in stroke }
    }

    private static func paragraphStyle(settings: ReaderSettings, title: Bool, fontName: String, numberTitle: Bool = false) -> CTParagraphStyle {
        var alignment: CTTextAlignment = title ? (settings.titleMode == 1 ? .center : settings.titleMode == 3 ? .right : .left)
            : settings.textFullJustify ? .justified : .left
        let currentFont = font(fontName, size: max(1, settings.textSize + (title ? settings.titleSize : 0)), weight: 0)
        let fontHeight = CTFontGetAscent(currentFont) + CTFontGetDescent(currentFont)
        var lineSpacing = CGFloat(title && !numberTitle ? (100 + Double(settings.configuration.titleLineSpacingExtra)) / 100 : settings.lineSpacingExtra / 10)
        lineSpacing = max(0.001, lineSpacing)
        var paragraphSpacing = title ? CGFloat(settings.titleBottomSpacing) : fontHeight * CGFloat(settings.paragraphSpacing) / 10
        var before = CGFloat(title ? settings.titleTopSpacing : 0)
        var lineBreak: CTLineBreakMode = settings.useZhLayout ? .byCharWrapping : .byWordWrapping
        var bounds: CTLineBoundsOptions = settings.hangingPunctuation ? .useHangingPunctuation : []
        return withUnsafePointer(to: &alignment) { alignment in
            withUnsafePointer(to: &lineSpacing) { lineSpacing in
                withUnsafePointer(to: &paragraphSpacing) { paragraphSpacing in
                    withUnsafePointer(to: &before) { before in
                        withUnsafePointer(to: &lineBreak) { lineBreak in
                            withUnsafePointer(to: &bounds) { bounds in
                                let values = [
                                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignment),
                                    CTParagraphStyleSetting(spec: .lineHeightMultiple, valueSize: MemoryLayout<CGFloat>.size, value: lineSpacing),
                                    CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: paragraphSpacing),
                                    CTParagraphStyleSetting(spec: .paragraphSpacingBefore, valueSize: MemoryLayout<CGFloat>.size, value: before),
                                    CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: MemoryLayout<CTLineBreakMode>.size, value: lineBreak),
                                    CTParagraphStyleSetting(spec: .lineBoundsOptions, valueSize: MemoryLayout<CTLineBoundsOptions>.size, value: bounds)
                                ]
                                return CTParagraphStyleCreate(values, values.count)
                            }
                        }
                    }
                }
            }
        }
    }
}

enum ReaderUnderline {
    static func draw(line: CTLine, origin: CGPoint, title: Bool, config: ReadBookConfig, context: CGContext, text: NSString? = nil) {
        guard (1...6).contains(config.underlineMode), config.underlineWidth > 0,
              title ? config.underlineTitleEnabled : config.underlineBodyEnabled else { return }
        context.saveGState()
        defer { context.restoreGState() }
        let width = min(10, config.underlineWidth)
        context.setLineWidth(width)
        let y = origin.y - min(30, max(0, config.underlineDistance))
        var segments: [(left: Double, right: Double, color: CGColor)] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard attributes[kCTRunDelegateAttributeName] == nil else { continue }
            let foreground = attributes[kCTForegroundColorAttributeName].map { $0 as! CGColor } ?? CGColor(gray: 0, alpha: 1)
            let color = config.underlineColorSet ? ReaderTypography.color(ARGBColor(UInt32(truncatingIfNeeded: config.underlineColor)).hex) : foreground
            let range = CTRunGetStringRange(run)
            var location = range.location
            if let text {
                let lineStart = CTLineGetStringRange(line).location
                if location == lineStart || segments.isEmpty {
                    while location < range.location + range.length, location < text.length,
                          let scalar = UnicodeScalar(text.character(at: location)), CharacterSet.whitespaces.contains(scalar) {
                        location += 1
                    }
                }
            }
            let start = origin.x + CTLineGetOffsetForStringIndex(line, location, nil)
            let end = origin.x + CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)
            let left = min(start, end), right = max(start, end)
            guard right > left else { continue }
            if let last = segments.last, abs(last.right - left) < 0.5, last.color == color {
                segments[segments.count - 1].right = right
            } else { segments.append((left, right, color)) }
        }
        for (left, right, color) in segments {
            context.setStrokeColor(color); context.setFillColor(color)
            func stroke(_ y: Double) {
                context.move(to: CGPoint(x: left, y: y)); context.addLine(to: CGPoint(x: right, y: y)); context.strokePath()
            }
            context.setLineDash(phase: 0, lengths: [2, 6].contains(config.underlineMode) ? [width * 4, width * 2] : [])
            switch config.underlineMode {
            case 3:
                let radius = max(0.5, width / 2)
                for x in stride(from: left + radius, through: right - radius, by: radius * 4) {
                    context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                }
            case 4, 6:
                let separation = (width + 1) / 2
                stroke(y - separation); stroke(y + separation)
            case 5:
                let amplitude = max(1, width), wavelength = max(4, width * 4)
                context.move(to: CGPoint(x: left, y: y))
                for x in stride(from: left + 0.5, through: right, by: 0.5) {
                    context.addLine(to: CGPoint(x: x, y: y + sin((x - left) * .pi * 2 / wavelength) * amplitude))
                }
                context.strokePath()
            default: stroke(y)
            }
        }
    }
}
