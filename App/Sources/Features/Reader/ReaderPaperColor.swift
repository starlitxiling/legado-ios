import CoreGraphics
import Foundation
import ImageIO

enum ReaderPaperColor {
    static func resolve(settings: ReaderSettings, image: CGImage? = nil) -> ARGBColor {
        if settings.backgroundType == 0 { return ARGBColor(hex: settings.backgroundValue) ?? ARGBColor(0xFFEEEEEE) }
        let base: Double = settings.theme == .night ? 0 : 255
        guard let image else { return ARGBColor(settings.theme == .night ? 0xFF000000 : 0xFFFFFFFF) }
        let width = min(32, image.width), height = min(32, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var totals = [Double](repeating: 0, count: 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<4 { totals[channel] += Double(bytes[index + channel]) }
        }
        let opacity = min(1, max(0, Double(settings.configuration.bgAlpha) / 100))
        let count = Double(width * height)
        let alpha = opacity * totals[3] / (count * 255)
        let channels = totals.prefix(3).map { UInt32(min(255, ($0 / count * opacity + base * (1 - alpha)).rounded())) }
        return ARGBColor(0xFF000000 | channels[0] << 16 | channels[1] << 8 | channels[2])
    }

    static func load(settings: ReaderSettings, directory: URL) async throws -> ARGBColor {
        guard let url = try settings.backgroundImageURL(directory: directory) else { return resolve(settings: settings) }
        return try await Task.detached {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 64] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
            return resolve(settings: settings, image: image)
        }.value
    }
}
