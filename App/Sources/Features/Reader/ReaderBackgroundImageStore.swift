import Foundation
import ImageIO
import UIKit

actor ReaderBackgroundImageStore {
    static let shared = ReaderBackgroundImageStore()
    private let cache = NSCache<NSString, UIImage>()
    private var pending: [String: Task<UIImage, Error>] = [:]

    init() {
        cache.totalCostLimit = 64 * 1024 * 1024
        cache.countLimit = 16
    }

    @MainActor static var screenPixelSize: Int {
        Int(max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height))
    }

    func image(at url: URL, maximumPixelSize: Int) async throws -> UIImage {
        let metadata = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = "\(url.absoluteString):\(maximumPixelSize):\(metadata.contentModificationDate?.timeIntervalSince1970 ?? 0):\(metadata.fileSize ?? 0)"
        if let image = cache.object(forKey: key as NSString) { return image }
        if let task = pending[key] { return try await task.value }
        let task = Task.detached {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.lastPathComponent])
            }
            return try Self.decode(source, maximumPixelSize: maximumPixelSize)
        }
        pending[key] = task
        defer { pending[key] = nil }
        let image = try await task.value
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
        return image
    }

    static func importedJPEG(_ data: Data, maximumPixelSize: Int) throws -> Data {
        guard data.count <= 30 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let image = try decode(source, maximumPixelSize: maximumPixelSize)
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
        return jpeg
    }

    private static func decode(_ source: CGImageSource, maximumPixelSize: Int) throws -> UIImage {
        guard maximumPixelSize > 0, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        return UIImage(cgImage: image)
    }
}
