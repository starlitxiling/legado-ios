import Foundation
import CoreGraphics
import ImageIO

actor CoverBitmapCache {
    static let shared = CoverBitmapCache()
    private let cache = NSCache<NSString, CGImage>()

    func image(_ data: Data, key: String, maximumPixels: Int, maximumMegabytes: Int) -> CGImage? {
        let limit = max(0, min(1024, maximumMegabytes)) * 1024 * 1024
        let pixels = max(1, min(4096, maximumPixels))
        cache.totalCostLimit = limit
        if limit == 0 { cache.removeAllObjects() }
        let cacheKey = "\(pixels):\(key)" as NSString
        if limit > 0, let image = cache.object(forKey: cacheKey) { return image }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels
              ] as CFDictionary) else { return nil }
        if limit > 0 { cache.setObject(image, forKey: cacheKey, cost: image.bytesPerRow * image.height) }
        return image
    }
}
