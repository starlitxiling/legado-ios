import Foundation
import CoreText

public struct ReaderTitleStyle {
    public var mode: Int
    public var sizeOffset: Double
    public var topSpacing: Double
    public var bottomSpacing: Double

    public init(mode: Int = 0, sizeOffset: Double = 0, topSpacing: Double = 0, bottomSpacing: Double = 0) {
        self.mode = mode; self.sizeOffset = sizeOffset
        self.topSpacing = topSpacing; self.bottomSpacing = bottomSpacing
    }

    public func attributes(fontName: String, bodySize: Double) -> [NSAttributedString.Key: Any] {
        var alignment: CTTextAlignment = mode == 1 ? .center : (mode == 3 ? .right : .left)
        var before = CGFloat(max(0, topSpacing)), after = CGFloat(max(0, bottomSpacing))
        let style = withUnsafePointer(to: &alignment) { alignment in
            withUnsafePointer(to: &before) { before in
                withUnsafePointer(to: &after) { after in
                    let values = [
                        CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignment),
                        CTParagraphStyleSetting(spec: .paragraphSpacingBefore, valueSize: MemoryLayout<CGFloat>.size, value: before),
                        CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: after)
                    ]
                    return CTParagraphStyleCreate(values, values.count)
                }
            }
        }
        return [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(fontName as CFString, max(1, bodySize + sizeOffset), nil),
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style]
    }
}
