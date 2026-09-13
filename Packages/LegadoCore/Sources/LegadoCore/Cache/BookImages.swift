import Foundation
import ImageIO
import UniformTypeIdentifiers
import SwiftSoup

extension BookHelp {
    public struct ChapterImage {
        public let range: NSRange
        public let url: String
    }

    public static func images(in content: String, chapter: BookChapter) throws -> [ChapterImage] {
        let regex = try NSRegularExpression(pattern: #"<img\b(?:[^>"']|"[^"]*"|'[^']*')*>"#, options: .caseInsensitive)
        let text = content as NSString
        let base = WebBookContext.absolute(chapter.url ?? "", base: chapter.baseUrl ?? "")
        return try regex.matches(in: content, range: NSRange(location: 0, length: text.length)).compactMap { match in
            let src = try SwiftSoup.parseBodyFragment(text.substring(with: match.range)).select("img").attr("src")
            guard !src.isEmpty else { return nil }
            return ChapterImage(range: match.range, url: WebBookContext.absolute(src, base: base))
        }
    }

    public static func imageFileName(_ src: String) -> String {
        let address = UrlOptions.parse(src).url
        let suffix = URL(string: address)?.pathExtension ?? ""
        let valid = suffix.range(of: #"^[a-zA-Z0-9]{1,5}$"#, options: .regularExpression) != nil
        return md5(src) + "." + (valid ? suffix : "jpg")
    }

    public static func imageURL(directory: URL, book: Book, src: String) -> URL {
        directory.appendingPathComponent("book_cache", isDirectory: true).appendingPathComponent(folderName(book), isDirectory: true)
            .appendingPathComponent("images", isDirectory: true).appendingPathComponent(imageFileName(src))
    }

    public static func imageData(directory: URL, book: Book, src: String) throws -> Data? {
        let url = imageURL(directory: directory, book: book, src: src)
        if FileManager.default.fileExists(atPath: url.path) { return try Data(contentsOf: url) }
        let root = directory.appendingPathComponent("book_cache", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(md5(book.bookUrl ?? "")) }.sorted { $0.path < $1.path }
        for folder in folders {
            let cached = folder.appendingPathComponent("images").appendingPathComponent(imageFileName(src))
            if FileManager.default.fileExists(atPath: cached.path) { return try Data(contentsOf: cached) }
        }
        return nil
    }

    public static func imageMediaType(_ data: Data) -> String? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? NSNumber, width.intValue > 0,
           let height = properties[kCGImagePropertyPixelHeight] as? NSNumber, height.intValue > 0,
           let type = CGImageSourceGetType(source) {
            switch type as String {
            case UTType.png.identifier: return "image/png"
            case UTType.jpeg.identifier: return "image/jpeg"
            case UTType.gif.identifier: return "image/gif"
            case UTType.tiff.identifier: return "image/tiff"
            case UTType.bmp.identifier: return "image/bmp"
            case UTType.webP.identifier: return "image/webp"
            default: return nil
            }
        }
        let parser = XMLParser(data: data), delegate = SVGImageSize()
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse() && delegate.valid ? "image/svg+xml" : nil
    }

    public static func hasImageContent(directory: URL, book: Book, chapter: BookChapter) -> Bool {
        guard hasContent(directory: directory, book: book, chapter: chapter) else { return false }
        do {
            guard let text = try content(directory: directory, book: book, chapter: chapter) else { return true }
            return try images(in: text, chapter: chapter).allSatisfy {
                guard let data = try imageData(directory: directory, book: book, src: $0.url) else { return false }
                return imageMediaType(data) != nil
            }
        } catch { return false }
    }

    public static func saveImages(source: BookSource, book: Book, chapter: BookChapter, content: String,
                                  directory: URL, client: any HttpClient, cookies: CookieStore = CookieStore()) async throws {
        let downloader = ImageDownloader(client: client, cacheDirectory: directory, cookies: cookies)
        var seen = Set<String>()
        for image in try images(in: content, chapter: chapter) where seen.insert(image.url).inserted {
            try Task.checkCancellation()
            if let cached = try imageData(directory: directory, book: book, src: image.url), imageMediaType(cached) != nil { continue }
            let destination = imageURL(directory: directory, book: book, src: image.url)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            let data = try await downloader.load(url: image.url, source: source, book: book, isCover: false, cacheFile: destination)
            guard imageMediaType(data) != nil else {
                try FileManager.default.removeItem(at: destination)
                throw ImageDownloadError.invalidDecodeResult
            }
        }
    }
}

private final class SVGImageSize: NSObject, XMLParserDelegate {
    private var isRoot = true
    var valid = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard isRoot else { return }
        isRoot = false
        guard elementName == "svg", attributeDict["xmlns"] == nil || attributeDict["xmlns"] == "http://www.w3.org/2000/svg" else { return }
        let viewBox = (attributeDict["viewBox"] ?? "").split { $0 == "," || $0.isWhitespace }.compactMap { Double($0) }
        if viewBox.count == 4, viewBox.allSatisfy(\.isFinite), viewBox[2] > 0, viewBox[3] > 0 { valid = true; return }
        func positive(_ value: String?) -> Bool {
            guard let value, let number = Double(value.replacingOccurrences(of: #"[a-zA-Z%]+$"#, with: "", options: .regularExpression)) else { return false }
            return number.isFinite && number > 0
        }
        valid = positive(attributeDict["width"]) && positive(attributeDict["height"])
    }
}
