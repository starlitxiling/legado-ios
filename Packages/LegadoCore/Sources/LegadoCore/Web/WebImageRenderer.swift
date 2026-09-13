import Foundation
import CoreGraphics
import ImageIO

enum WebImageRenderer {
    static func png(_ data: Data?, width: Int, cover: Bool) throws -> Data {
        guard (1...4096).contains(width) else { throw WebHttpError.malformed }
        var image: CGImage?
        if let data, let source = CGImageSourceCreateWithData(data as CFData, nil) {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, cover ? 112 : width),
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary)
        }
        guard image != nil || cover else { throw ImageDownloadError.emptyImage }
        let height = cover ? 112 : max(1, min(16384, Int(Double(image!.height) * Double(width) / Double(image!.width))))
        guard width * height <= 16_777_216,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw WebHttpError.tooLarge }
        context.setFillColor(CGColor(gray: 0.85, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let image {
            let scale = max(Double(width) / Double(image.width), Double(height) / Double(image.height))
            let w = Double(image.width) * scale, h = Double(image.height) * scale
            context.draw(image, in: CGRect(x: (Double(width) - w) / 2, y: (Double(height) - h) / 2, width: w, height: h))
        }
        guard let output = context.makeImage() else { throw ImageDownloadError.emptyImage }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil) else { throw ImageDownloadError.emptyImage }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageDownloadError.emptyImage }
        return bytes as Data
    }
}
