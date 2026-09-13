import Foundation

public enum LocalBookError: Error, LocalizedError {
    case identityConflict(String, String)
    case unsupportedFile, invalidEncoding, emptyFile, invalidOffsets, invalidEPUB(String)
    public var errorDescription: String? {
        switch self {
        case .identityConflict(let name, let author): return "书架已存在同名同作者书籍：\(name) / \(author)"
        case .unsupportedFile: return "只支持本地 TXT 和 EPUB 文件。"
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

    public init(url: URL, blockSize: Int = 64 * 1024) throws {
        self.url = url; self.blockSize = max(4, blockSize)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 64 * 1024) ?? Data()
        guard !data.isEmpty else { throw LocalBookError.emptyFile }
        let detected = TextEncodingDetector.detect(data, truncated: data.count == 64 * 1024)
        charset = detected.name; encoding = detected.encoding; bomSize = detected.bomSize
    }

    public func chapters(bookURL: String, rules: [TxtTocRule] = TxtTocRule.builtIn) throws -> [BookChapter] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = Int64(try handle.seekToEnd())
        guard size > bomSize else { throw LocalBookError.emptyFile }
        try handle.seek(toOffset: UInt64(bomSize))
        let window = 256 * 1024
        var buffer = Data(), base = Int64(bomSize), eligible = Int64(bomSize), lastEnd = Int64(bomSize)
        var selected: (TxtTocRule, NSRegularExpression)?
        var didSelect = false, eof = false
        var chapters: [BookChapter] = []
        func append(_ title: String, start: Int64) {
            var chapter = BookChapter()
            chapter.bookUrl = bookURL; chapter.baseUrl = bookURL
            chapter.index = chapters.count; chapter.url = "txt:\(chapters.count)"
            chapter.title = title; chapter.start = start; chapter.end = size
            chapters.append(chapter)
        }
        func validPrefix(_ data: Data, limit: Int) throws -> Int {
            for count in stride(from: min(limit, data.count), through: max(0, min(limit, data.count) - 3), by: -1) {
                if String(data: data.prefix(count), encoding: encoding) != nil { return count }
            }
            throw LocalBookError.invalidEncoding
        }
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
            if !didSelect {
                var bestCount = 0
                for rule in rules.filter({ $0.enable && !$0.rule.isEmpty }).sorted(by: { $0.serialNumber < $1.serialNumber }) {
                    guard let regex = try? NSRegularExpression(pattern: rule.rule, options: [.anchorsMatchLines]) else { continue }
                    let count = regex.numberOfMatches(in: text, range: range)
                    if count > 0 && (selected == nil || count > bestCount + 2) {
                        selected = (rule, regex); bestCount = count
                    }
                }
                didSelect = true
                if selected == nil { append("正文", start: Int64(bomSize)) }
            }
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
                    let title = (rule.replacement.isEmpty ? raw : regex.replacementString(for: match, in: text, offset: 0, template: rule.replacement))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { continue }
                    if chapters.isEmpty && start > Int64(bomSize) { append("前言", start: Int64(bomSize)) }
                    if !chapters.isEmpty { chapters[chapters.count - 1].end = start }
                    append(title, start: end); lastEnd = end
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
        return chapters
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
