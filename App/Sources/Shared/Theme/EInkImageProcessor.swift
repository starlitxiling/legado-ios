import CoreGraphics
import Foundation

/// Renders images the way an e-paper panel can show them: flattened onto white and reduced to
/// grayscale, 16 gray levels, black-and-white error diffusion, or a hard threshold.
enum EInkImageProcessor {
    static let maximumPixels = 4_000_000

    static func process(_ image: CGImage, mode: EInkSettings.ImageMode, threshold: Int) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width * height <= maximumPixels,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(rect)
        context.draw(image, in: rect)
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        let buffer = UnsafeMutableBufferPointer(start: pixels, count: width * height)
        switch mode {
        case .gray: break
        case .levels: quantize(buffer)
        case .threshold: binarize(buffer, threshold: threshold)
        case .dither: diffuse(buffer, width: width, height: height)
        }
        return context.makeImage()
    }

    static func quantize(_ pixels: UnsafeMutableBufferPointer<UInt8>) {
        for index in pixels.indices { pixels[index] = UInt8((Int(pixels[index]) + 8) / 17 * 17) }
    }

    static func binarize(_ pixels: UnsafeMutableBufferPointer<UInt8>, threshold: Int) {
        let limit = UInt8(clamping: min(255, max(1, threshold)))
        for index in pixels.indices { pixels[index] = pixels[index] >= limit ? 255 : 0 }
    }

    /// Floyd–Steinberg error diffusion to pure black and white.
    static func diffuse(_ pixels: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int) {
        var current = [Int](repeating: 0, count: width + 2)
        var next = [Int](repeating: 0, count: width + 2)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let value = Int(pixels[index]) + current[x + 1] / 16
                let output = value >= 128 ? 255 : 0
                pixels[index] = UInt8(output)
                let error = value - output
                current[x + 2] += error * 7
                next[x] += error * 3
                next[x + 1] += error * 5
                next[x + 2] += error
            }
            swap(&current, &next)
            for index in next.indices { next[index] = 0 }
        }
    }
}
