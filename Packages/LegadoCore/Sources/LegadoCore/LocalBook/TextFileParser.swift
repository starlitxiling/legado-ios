import Foundation

public enum LocalBookError: Error, LocalizedError {
    case identityConflict(String, String)
    case unsupportedFile, invalidEncoding, emptyFile, invalidOffsets, invalidEPUB(String)
    public var errorDescription: String? {
        switch self {
        case .identityConflict(let name, let author): return "书架已存在同名同作者书籍：\(name) / \(author)"
        case .unsupportedFile: return "只支持本地 TXT、EPUB、UMD、MOBI、AZW3、AZW 和 PDF 文件。"
        case .invalidEncoding: return "无法识别文本编码。"
        case .emptyFile: return "文件中没有正文。"
        case .invalidOffsets: return "章节偏移超出文件范围，请重新导入。"
        case .invalidEPUB(let reason): return "EPUB 解析失败：\(reason)"
        }
    }
}

public struct TextFileParser {
    public let url: URL
    public let charset: String
    private let encoding: String.Encoding
    private let bomSize: Int
    private let blockSize: Int

    public init(url: URL, blockSize: Int = 64 * 1024, charset preferredCharset: String? = nil) throws {
        self.url = url; self.blockSize = max(4, blockSize)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 512_000) ?? Data()
        guard !data.isEmpty else { throw LocalBookError.emptyFile }
        let detected = TextEncodingDetector.detect(data, truncated: data.count == 512_000)
        if let preferredCharset, !preferredCharset.isEmpty {
            charset = preferredCharset; encoding = try ResponseDecoder.encoding(for: preferredCharset)
        } else { charset = detected.name; encoding = detected.encoding }
        bomSize = detected.bomSize
    }

    public func selectedRule(rules: [TxtTocRule], book: Book = Book()) throws -> TxtTocRule? {
        try chooseRule(rules: rules, processor: TxtTitleProcessor(book: book))
    }

    private func chooseRule(rules: [TxtTocRule], processor: TxtTitleProcessor) throws -> TxtTocRule? {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try file.seek(toOffset: UInt64(bomSize))
        let sample = try file.read(upToCount: 512_000) ?? Data()
        for suffix in 0...min(3, sample.count) {
            if let text = String(data: sample.dropLast(suffix), encoding: encoding) {
                return try processor.select(content: text, rules: rules)
            }
        }
        throw LocalBookError.invalidEncoding
    }

    public func chapters(bookURL: String, rules: [TxtTocRule] = TxtTocRule.builtIn, book: Book? = nil,
                         selectedRule: TxtTocRule? = nil, splitLongChapters: Bool = true,
                         autoSelectRule: Bool = true) throws -> [BookChapter] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = Int64(try handle.seekToEnd())
        guard size > bomSize else { throw LocalBookError.emptyFile }
        try handle.seek(toOffset: UInt64(bomSize))
        let window = 256 * 1024
        var buffer = Data(), base = Int64(bomSize), eligible = Int64(bomSize), lastEnd = Int64(bomSize)
        let processor = TxtTitleProcessor(book: book ?? Book())
        let rule = try selectedRule ?? (autoSelectRule ? chooseRule(rules: rules, processor: processor) : nil)
        processor.setVolumeTitle("")
        let selected = try rule.map { ($0, try NSRegularExpression(pattern: $0.rule, options: [.anchorsMatchLines])) }
        var eof = false
        var chapters: [BookChapter] = []
        func append(_ title: String, start: Int64) {
            var chapter = BookChapter()
            chapter.bookUrl = bookURL; chapter.baseUrl = bookURL
            chapter.index = chapters.count
            chapter.title = title; chapter.start = start; chapter.end = size
            chapters.append(chapter)
        }
        func validPrefix(_ data: Data, limit: Int) throws -> Int {
            for count in stride(from: min(limit, data.count), through: max(0, min(limit, data.count) - 3), by: -1) {
                if String(data: data.prefix(count), encoding: encoding) != nil { return count }
            }
            throw LocalBookError.invalidEncoding
        }
        func finishChapter(at end: Int64) throws {
            guard !chapters.isEmpty else { return }
            let index = chapters.count - 1
            chapters[index].end = end
            let length = end - (chapters[index].start ?? 0)
            if selected != nil, splitLongChapters, length > 102_400 {
                let children = try subdivide(chapters[index])
                chapters[index].isVolume = true
                chapters[index].end = chapters[index].start
                processor.setVolumeTitle(chapters[index].title ?? "")
                chapters.append(contentsOf: children)
            } else if selected != nil, length < 400,
                      try content(chapter: chapters[index]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chapters[index].isVolume = true
                processor.setVolumeTitle(chapters[index].title ?? "")
            }
        }
        if selected == nil { append("正文", start: Int64(bomSize)) }
        while !eof {
            while buffer.count < 3 * window {
                let block = try handle.read(upToCount: min(blockSize, 3 * window - buffer.count)) ?? Data()
                if block.isEmpty { eof = true; break }
                buffer.append(block)
            }
            try Task.checkCancellation()
            let decodedCount = try validPrefix(buffer, limit: buffer.count)
            if eof && decodedCount != buffer.count { throw LocalBookError.invalidEncoding }
            let prefix = base == Int64(bomSize) ? "\n" : ""
            let decodedText = String(data: buffer.prefix(decodedCount), encoding: encoding)!
            let text = prefix + decodedText
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            let safeEnd = eof ? size : base + Int64(try validPrefix(buffer, limit: decodedCount - window))
            var offsets = [Int64](repeating: base, count: ns.length + 1)
            var characterOffset = prefix.utf16.count, bytePosition = base
            for scalar in decodedText.unicodeScalars {
                let value = String(scalar)
                let units = value.utf16.count
                for index in 0..<units { offsets[characterOffset + index] = bytePosition }
                bytePosition += Int64(value.data(using: encoding)!.count)
                characterOffset += units; offsets[characterOffset] = bytePosition
            }
            func byteOffset(_ location: Int) -> Int64 { offsets[location] }
            if let (rule, regex) = selected {
                for match in regex.matches(in: text, range: range) where match.range.length > 0 && match.range.location >= prefix.utf16.count {
                    let start = byteOffset(match.range.location), end = byteOffset(NSMaxRange(match.range))
                    guard start >= eligible, start >= lastEnd, start < safeEnd else { continue }
                    let raw = ns.substring(with: match.range)
                    if chapters.isEmpty && start > Int64(bomSize) {
                        var front = BookChapter(); front.start = Int64(bomSize); front.end = start
                        if try !content(chapter: front).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let heading = try processor.replace("前言", script: rule.replacement, index: 1,
                                previousTitle: nil, previousLength: -1)
                            for volume in heading.volumes {
                                append(volume, start: Int64(bomSize))
                                chapters[chapters.count - 1].end = Int64(bomSize)
                                chapters[chapters.count - 1].isVolume = true
                            }
                            if !heading.title.isEmpty { append(heading.title, start: Int64(bomSize)) }
                            if !chapters.isEmpty { chapters[chapters.count - 1].end = start }
                        }
                    }
                    let previous = chapters.last
                    var previousLength = -1
                    if !rule.replacement.isEmpty, var previous {
                        previous.end = start
                        previousLength = try contentLength(chapter: previous)
                        if splitLongChapters && start - (previous.start ?? 0) > 102_400 { processor.setVolumeTitle(previous.title ?? "") }
                    }
                    let replacement = try processor.replace(raw, script: rule.replacement, index: chapters.count + 1,
                        previousTitle: previous?.title, previousLength: previousLength)
                    let title = replacement.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty || !replacement.volumes.isEmpty else { continue }
                    try finishChapter(at: start)
                    for volume in replacement.volumes {
                        append(volume, start: start)
                        chapters[chapters.count - 1].end = start
                        chapters[chapters.count - 1].isVolume = true
                    }
                    if !title.isEmpty { append(title, start: end) }
                    lastEnd = end
                }
            } else {
                let newline = try NSRegularExpression(pattern: "\\n")
                for match in newline.matches(in: text, range: range) where match.range.location >= prefix.utf16.count {
                    let end = byteOffset(NSMaxRange(match.range))
                    if end >= eligible, end <= safeEnd, end < size, end - (chapters.last?.start ?? 0) >= 10 * 1024 {
                        chapters[chapters.count - 1].end = end
                        append("第\(chapters.count + 1)章", start: end)
                    }
                }
            }
            eligible = safeEnd
            if !eof {
                let drop = try validPrefix(buffer, limit: window)
                buffer = Data(buffer.dropFirst(drop)); base += Int64(drop)
            }
        }
        if chapters.isEmpty { append("正文", start: Int64(bomSize)) }
        try finishChapter(at: size)
        let originName = book?.originName.flatMap { $0.isEmpty ? nil : $0 } ?? url.lastPathComponent
        for index in chapters.indices {
            chapters[index].index = index
            chapters[index].url = TxtTitleProcessor.chapterURL(originName: originName, index: index, title: chapters[index].title ?? "")
        }
        return chapters
    }

    private func forEachScalar(chapter: BookChapter, _ visit: (UnicodeScalar, Int64) -> Void) throws {
        guard let start = chapter.start, let end = chapter.end, start >= 0, end >= start else { throw LocalBookError.invalidOffsets }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try file.seek(toOffset: UInt64(start))
        var position = start, buffer = Data()
        while position < end {
            try Task.checkCancellation()
            let read = try file.read(upToCount: Int(min(64 * 1024, end - position - Int64(buffer.count)))) ?? Data()
            buffer.append(read)
            var decoded: (String, Int)?
            for suffix in 0...min(3, buffer.count) {
                if let text = String(data: buffer.dropLast(suffix), encoding: encoding) { decoded = (text, buffer.count - suffix); break }
            }
            guard let (text, consumed) = decoded, consumed > 0 else { throw LocalBookError.invalidEncoding }
            for scalar in text.unicodeScalars {
                position += Int64(String(scalar).data(using: encoding)!.count)
                visit(scalar, position)
            }
            buffer = Data(buffer.dropFirst(consumed))
        }
        guard buffer.isEmpty else { throw LocalBookError.invalidEncoding }
    }

    private func contentLength(chapter: BookChapter) throws -> Int {
        var length = 0
        try forEachScalar(chapter: chapter) { scalar, _ in length += scalar.value > 0xffff ? 2 : 1 }
        return length
    }

    private func subdivide(_ chapter: BookChapter) throws -> [BookChapter] {
        var result: [BookChapter] = [], start = chapter.start ?? 0
        func append(end: Int64) {
            var child = chapter
            child.title = (chapter.title ?? "") + "(\(result.count + 1))"
            child.start = start; child.end = end; child.isVolume = false
            result.append(child); start = end
        }
        try forEachScalar(chapter: chapter) { scalar, offset in
            if (scalar.value == 10 && offset - start >= 10 * 1024) || offset - start >= 512_000 { append(end: offset) }
        }
        if let end = chapter.end, start < end { append(end: end) }
        return result
    }

    public func content(chapter: BookChapter) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard let start = chapter.start, let end = chapter.end, start >= 0, end >= start, UInt64(end) <= size,
              end - start <= Int64(Int.max) else { throw LocalBookError.invalidOffsets }
        try handle.seek(toOffset: UInt64(start))
        let data = try handle.read(upToCount: Int(end - start)) ?? Data()
        guard data.count == Int(end - start), let text = String(data: data, encoding: encoding) else { throw LocalBookError.invalidEncoding }
        return text
    }
}
