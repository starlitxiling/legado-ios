import Foundation
import CoreText
import CoreGraphics
import ImageIO
import LegadoCore

struct ReaderPlacedImage {
    let offset: Int
    let url: String
    let click: String?
    let rect: CGRect
}

struct ReaderImageSpec {
    let offset: Int
    let url: String
    let click: String?
    let style: String
    let size: CGSize
}

enum ReaderImageLayout {
    static let imageKey = NSAttributedString.Key("LegadoInlineImage")
    private final class Metrics {
        let size: CGSize
        init(_ size: CGSize) { self.size = size }
    }

    static func delegate(size: CGSize) -> CTRunDelegate? {
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1,
            dealloc: { pointer in Unmanaged<Metrics>.fromOpaque(pointer).release() },
            getAscent: { pointer in Unmanaged<Metrics>.fromOpaque(pointer).takeUnretainedValue().size.height },
            getDescent: { _ in 0 },
            getWidth: { pointer in Unmanaged<Metrics>.fromOpaque(pointer).takeUnretainedValue().size.width })
        let pointer = Unmanaged.passRetained(Metrics(size)).toOpaque()
        guard let delegate = CTRunDelegateCreate(&callbacks, pointer) else { Unmanaged<Metrics>.fromOpaque(pointer).release(); return nil }
        return delegate
    }

    static func spec(offset: Int, url: String, style: String, natural: CGSize?, available: CGSize, textSize: Double) throws -> ReaderImageSpec {
        let attributes = try CustomUrl(url).getAttr()
        let chosen = (attributes["style"] as? String ?? style).uppercased()
        var natural = natural ?? CGSize(width: 400, height: 300)
        if natural.width <= 0 || natural.height <= 0 || !natural.width.isFinite || !natural.height.isFinite { natural = CGSize(width: 400, height: 300) }
        if let width = attributes["width"].map({ String(describing: $0) }) {
            let value = width.hasSuffix("%") ? Double(width.dropLast()).map { $0 * available.width / 100 } : Double(width)
            if let value, value.isFinite, value > 0 {
                let height = natural.height / natural.width * value
                if height.isFinite { natural = CGSize(width: value, height: height) }
            }
        }
        let size: CGSize
        if chosen == "TEXT" {
            let height = min(available.height, textSize)
            size = CGSize(width: min(available.width, height * natural.width / natural.height), height: height)
        } else {
            let scale = ["FULL", "SINGLE"].contains(chosen) ? available.width / natural.width : min(1, available.width / natural.width)
            let fitted = min(scale, available.height / natural.height)
            size = CGSize(width: natural.width * fitted, height: natural.height * fitted)
        }
        return ReaderImageSpec(offset: offset, url: url, click: attributes["click"] as? String, style: chosen, size: size)
    }

    static func naturalSize(_ data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }
}

enum ReaderImageAction: Equatable {
    case none, consume, preview, script(String, String)

    static func resolve(_ image: ReaderPlacedImage, mode: String, taps: Int, onlineText: Bool) throws -> Self {
        if mode == "3" { return .none }
        if mode == "4", taps == 1 { return .consume }
        guard taps == (mode == "4" ? 2 : 1) else { return .none }
        if mode == "1" { return .preview }
        if mode == "2", !onlineText { return .none }
        if let click = image.click, !click.isEmpty { return .script(click, image.url) }
        if mode == "2", let legacy = try CustomUrl(image.url).getAttr()["js"] as? String {
            return .script(legacy, CustomUrl(image.url).getUrl())
        }
        return .none
    }
}
