import UIKit
import CryptoKit

@MainActor
enum CoverBitmapCache {
    private static let cache = NSCache<NSString, UIImage>()
    static func image(_ data: Data, maximumMegabytes: Int) -> UIImage? {
        let limit = max(0, min(1024, maximumMegabytes)) * 1024 * 1024
        cache.totalCostLimit = limit
        if limit == 0 { cache.removeAllObjects(); return UIImage(data: data) }
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let image = UIImage(data: data) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
