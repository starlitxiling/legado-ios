import Foundation

public struct BookExporter {
    public struct Chapter {
        public let chapter: BookChapter
        public let content: String
        public init(chapter: BookChapter, content: String) { self.chapter = chapter; self.content = content }
    }
    public struct Cover {
        public let data: Data
        public let mediaType: String
        public init(data: Data, mediaType: String) { self.data = data; self.mediaType = mediaType }
    }
    public enum ExportError: Error { case invalidRange, unsupportedCover, archiveTooLarge, missingImage(String) }
    private let book: Book
    private let chapters: [Chapter]
    private let processor: ContentProcessor
    private let createdAt: Date
    private let imageLoader: (String) throws -> Data?

    public init(book: Book, chapters: [Chapter], rules: [ReplaceRule] = [], createdAt: Date = Date(),
                imageLoader: @escaping (String) throws -> Data? = { _ in nil }) {
        self.book = book
        self.chapters = chapters.sorted { $0.chapter.index < $1.chapter.index }
        processor = ContentProcessor(rules: rules)
        self.createdAt = createdAt
        self.imageLoader = imageLoader
    }

    private func selected(_ range: ClosedRange<Int>?) throws -> [Chapter] {
        guard !chapters.isEmpty else { throw ExportError.invalidRange }
        guard let range else { return chapters }
        guard range.lowerBound >= chapters[0].chapter.index, range.upperBound <= chapters.last!.chapter.index else {
            throw ExportError.invalidRange
        }
        let result = chapters.filter { range.contains($0.chapter.index) }
        guard !result.isEmpty else { throw ExportError.invalidRange }
        return result
    }

    public func txt(range: ClosedRange<Int>? = nil, useReplace: Bool = true) throws -> String {
        var text = "\(book.name ?? "")\n作者：\(book.author ?? "")\n简介：\n\(HtmlFormatter.format(book.customIntro ?? book.intro))"
        for item in try selected(range) {
            var chapter = item.chapter; chapter.isVip = false
            text += "\n\n" + HtmlFormatter.formatIntro(try processor.getContent(book: book, chapter: chapter, content: item.content,
                                                                              useReplace: useReplace).text)
        }
        return text
    }

    public func epub(range: ClosedRange<Int>? = nil, useReplace: Bool = true, cover: Cover? = nil) throws -> Data {
        let selected = try selected(range)
        let identifier = Self.xml(book.bookUrl ?? book.name ?? "Legado")
        let date = ISO8601DateFormatter().string(from: createdAt)
        var files: [(String, Data)] = []
        func add(_ name: String, _ text: String) { files.append((name, Data(text.utf8))) }
        add("mimetype", "application/epub+zip")
        add("META-INF/container.xml", """
            <?xml version="1.0" encoding="UTF-8"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
            """)
        var manifest = "<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>"
        var spine = "", navigation = "", coverMeta = "", guide = ""
        var embeddedImages = Set<String>()
        var rewrittenImages: [String: String] = [:]
        func imageMarkup(_ text: String, chapter: BookChapter, escapeText: Bool) throws -> String {
            let input = text as NSString
            var position = 0, output = ""
            let base = WebBookContext.absolute(chapter.url ?? "", base: chapter.baseUrl ?? "")
            for image in try BookHelp.images(in: text, chapter: chapter) {
                let preceding = input.substring(with: NSRange(location: position, length: image.range.location - position))
                output += escapeText ? Self.xml(preceding) : preceding
                let name = BookHelp.imageFileName(image.url), href = rewrittenImages[image.url] ?? "Images/" + name
                if embeddedImages.insert(href).inserted {
                    guard let data = try imageLoader(image.url), let mediaType = BookHelp.imageMediaType(data) else {
                        throw ExportError.missingImage(image.url)
                    }
                    files.append(("OEBPS/" + href, data))
                    manifest += "<item id=\"image_\(name)\" href=\"\(href)\" media-type=\"\(mediaType)\"/>"
                }
                rewrittenImages[WebBookContext.absolute("../" + href, base: base)] = href
                output += "<img src=\"../\(href)\" alt=\"\"/>"
                position = NSMaxRange(image.range)
            }
            let remaining = input.substring(from: position)
            output += escapeText ? Self.xml(remaining) : remaining
            return output
        }
        if let cover {
            let ext: String
            switch cover.mediaType {
            case "image/jpeg": ext = "jpg"
            case "image/png": ext = "png"
            default: throw ExportError.unsupportedCover
            }
            files.append(("OEBPS/Images/cover." + ext, cover.data))
            add("OEBPS/Text/cover.html", Self.xhtml(title: "封面", body: "<div><img src=\"../Images/cover.\(ext)\" alt=\"封面\"/></div>"))
            manifest += "<item id=\"cover-image\" href=\"Images/cover.\(ext)\" media-type=\"\(cover.mediaType)\"/><item id=\"cover\" href=\"Text/cover.html\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"cover\" linear=\"no\"/>"
            coverMeta = "<meta name=\"cover\" content=\"cover-image\"/>"
            guide = "<guide><reference type=\"cover\" title=\"封面\" href=\"Text/cover.html\"/></guide>"
        }
        for (position, item) in selected.enumerated() {
            try Task.checkCancellation()
            var chapter = item.chapter; chapter.isVip = false
            let id = "chapter_\(chapter.index)"
            let title = try processor.title(book: book, chapter: chapter, useReplace: useReplace)
            let prepared = try imageMarkup(item.content, chapter: chapter, escapeText: false)
            let content = try processor.getContent(book: book, chapter: chapter, content: prepared,
                                                  includeTitle: false, useReplace: useReplace)
            let body = "<h1>\(Self.xml(title))</h1>" + (try content.paragraphs.map {
                "<p>" + (try imageMarkup($0, chapter: chapter, escapeText: true)) + "</p>"
            }.joined())
            add("OEBPS/Text/\(id).html", Self.xhtml(title: title, body: body))
            manifest += "<item id=\"\(id)\" href=\"Text/\(id).html\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"\(id)\"/>"
            navigation += "<navPoint id=\"\(id)\" playOrder=\"\(position + 1)\"><navLabel><text>\(Self.xml(title))</text></navLabel><content src=\"Text/\(id).html\"/></navPoint>"
        }
        add("OEBPS/content.opf", """
            <?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="book-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>\(Self.xml(book.name ?? ""))</dc:title><dc:creator>\(Self.xml(book.author ?? ""))</dc:creator><dc:language>zh</dc:language><dc:date>\(date)</dc:date><dc:publisher>Legado</dc:publisher><dc:description>\(Self.xml(book.customIntro ?? book.intro ?? ""))</dc:description><dc:identifier id="book-id">\(identifier)</dc:identifier>\(coverMeta)</metadata><manifest>\(manifest)</manifest><spine toc="ncx">\(spine)</spine>\(guide)</package>
            """)
        add("OEBPS/toc.ncx", """
            <?xml version="1.0" encoding="UTF-8"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="\(identifier)"/><meta name="dtb:depth" content="1"/><meta name="dtb:totalPageCount" content="0"/><meta name="dtb:maxPageNumber" content="0"/></head><docTitle><text>\(Self.xml(book.name ?? ""))</text></docTitle><navMap>\(navigation)</navMap></ncx>
            """)
        return try Self.zip(files)
    }

    private static func xml(_ text: String) -> String {
        String(text.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || ($0.value >= 32 && $0.value != 0xfffe && $0.value != 0xffff) })
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func xhtml(title: String, body: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>\(xml(title))</title></head><body>\(body)</body></html>"
    }

    private static func zip(_ files: [(String, Data)]) throws -> Data {
        guard files.count < 65535 else { throw ExportError.archiveTooLarge }
        var data = Data(), central = Data()
        func number(_ value: Int, _ bytes: Int, into output: inout Data) {
            for shift in 0..<bytes { output.append(UInt8(truncatingIfNeeded: value >> (shift * 8))) }
        }
        for (name, payload) in files {
            try Task.checkCancellation()
            let filename = Data(name.utf8), offset = data.count, crc = Int(BackupArchive.crc32(payload))
            guard payload.count < Int(UInt32.max), offset < Int(UInt32.max), filename.count < 65535 else { throw ExportError.archiveTooLarge }
            number(0x04034b50, 4, into: &data)
            for value in [20, 0x800, 0, 0, 33] { number(value, 2, into: &data) }
            for value in [crc, payload.count, payload.count] { number(value, 4, into: &data) }
            number(filename.count, 2, into: &data); number(0, 2, into: &data)
            data.append(filename); data.append(payload)
            number(0x02014b50, 4, into: &central)
            for value in [20, 20, 0x800, 0, 0, 33] { number(value, 2, into: &central) }
            for value in [crc, payload.count, payload.count] { number(value, 4, into: &central) }
            for value in [filename.count, 0, 0, 0, 0] { number(value, 2, into: &central) }
            number(0, 4, into: &central); number(offset, 4, into: &central); central.append(filename)
        }
        let offset = data.count
        guard offset < Int(UInt32.max), central.count < Int(UInt32.max) else { throw ExportError.archiveTooLarge }
        data.append(central)
        number(0x06054b50, 4, into: &data)
        for value in [0, 0, files.count, files.count] { number(value, 2, into: &data) }
        number(central.count, 4, into: &data); number(offset, 4, into: &data); number(0, 2, into: &data)
        return data
    }
}
