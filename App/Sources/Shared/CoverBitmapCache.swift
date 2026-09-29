import Foundation
import CoreGraphics
import ImageIO

actor CoverBitmapCache {
    static let shared = CoverBitmapCache()
    private final class Entry {
        let image: CGImage
        let pixels: Int
        init(image: CGImage, pixels: Int) { self.image = image; self.pixels = pixels }
    }
    private let cache = NSCache<NSString, Entry>()

    static func key(address: String, origin: String?, bookURL: String?) -> String {
        var key = address + "|" + (origin ?? "") + "|" + (bookURL ?? "")
        let local = address.hasPrefix("/") ? URL(fileURLWithPath: address) : URL(string: address)
        if let local, local.isFileURL,
           let attributes = try? FileManager.default.attributesOfItem(atPath: local.path) {
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            key += "|\(modified)|\((attributes[.size] as? NSNumber)?.int64Value ?? 0)"
        }
        return key
    }

    func cached(key: String, maximumPixels: Int, maximumMegabytes: Int) -> CGImage? {
        guard max(0, min(1024, maximumMegabytes)) > 0, let entry = cache.object(forKey: key as NSString),
              entry.pixels >= max(1, min(4096, maximumPixels)) else { return nil }
        return entry.image
    }

    func image(_ data: Data, key: String, maximumPixels: Int, maximumMegabytes: Int) -> CGImage? {
        let limit = max(0, min(1024, maximumMegabytes)) * 1024 * 1024
        let pixels = max(1, min(4096, maximumPixels))
        cache.totalCostLimit = limit
        if limit == 0 { cache.removeAllObjects() }
        if limit > 0, let image = cached(key: key, maximumPixels: pixels, maximumMegabytes: maximumMegabytes) { return image }
        guard !Task.isCancelled, let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels
              ] as CFDictionary) else { return nil }
        if limit > 0 { cache.setObject(Entry(image: image, pixels: pixels), forKey: key as NSString, cost: image.bytesPerRow * image.height) }
        return image
    }
}
