import Foundation
import zlib

public enum UmdError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let reason): return "UMD 解析失败：\(reason)" }
    }
}

public final class UmdFile {
    public let title: String
    public let author: String
    public let kind: String
    public let cover: Data?
    private let titles: [String]
    private let offsets: [Int]
    private let contents: Data
    var cacheCost: Int { contents.count + (cover?.count ?? 0) + titles.reduce(0) { $0 + $1.utf8.count } }

    public convenience init(url: URL, maximumExpandedSize: Int = 64 * 1024 * 1024) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe), maximumExpandedSize: maximumExpandedSize)
    }

    public init(data: Data, maximumExpandedSize: Int = 64 * 1024 * 1024) throws {
        var input = Cursor(data: Data(data))
        guard maximumExpandedSize > 0, try input.number(4) == 0xde9a9b89 else {
            throw UmdError.invalid("Invalid header or expansion limit")
        }
        var title = "", author = "", kind = ""
        var cover: Data?, titles: [String] = [], offsets: [Int] = [], contents = Data()
        var section = 0, check = 0, declaredSize: Int?, ended = false, textBook = false
        while !input.isAtEnd {
            try Task.checkCancellation()
            let marker = try input.number(1)
            if marker == 35 {
                let type = try input.number(2)
                _ = try input.number(1)
                let length = try input.number(1)
                guard length >= 5 else { throw UmdError.invalid("Invalid section length") }
                var payload = Cursor(data: try input.read(length - 5))
                switch type {
                case 1:
                    guard try payload.number(1) == 1 else { throw UmdError.invalid("Unsupported image-book type") }
                    _ = try payload.number(2)
                    textBook = true
                case 2: title = try Self.decode(payload.data)
                case 3: author = try Self.decode(payload.data)
                case 7: kind = try Self.decode(payload.data)
                case 11:
                    declaredSize = try payload.number(4)
                    guard let declaredSize, declaredSize > 0, declaredSize <= maximumExpandedSize else {
                        throw UmdError.invalid("Declared content exceeds expansion limit")
                    }
                case 12:
                    guard try payload.number(4) == data.count, input.isAtEnd else {
                        throw UmdError.invalid("Invalid final file length")
                    }
                    ended = true
                case 129, 131, 132: check = try payload.number(4)
                case 130:
                    _ = try payload.number(1)
                    check = try payload.number(4)
                default: break
                }
                if type != 241 && type != 10 { section = type }
            } else if marker == 36 {
                let additionalCheck = try input.number(4)
                let length = try input.number(4)
                guard length >= 9 else { throw UmdError.invalid("Invalid additional section length") }
                let payload = try input.read(length - 9)
                switch section {
                case 130:
                    guard payload.count <= maximumExpandedSize - contents.count else { throw UmdError.invalid("Cover exceeds expansion limit") }
                    cover = payload
                case 131:
                    guard offsets.isEmpty, payload.count % 4 == 0, payload.count / 4 <= 100_000 else {
                        throw UmdError.invalid("Invalid chapter offset table")
                    }
                    var table = Cursor(data: payload)
                    while !table.isAtEnd { offsets.append(try table.number(4)) }
                case 132:
                    if additionalCheck == check {
                        guard titles.isEmpty, !offsets.isEmpty else { throw UmdError.invalid("Invalid title table order") }
                        var table = Cursor(data: payload)
                        for _ in offsets {
                            let length = try table.number(1)
                            titles.append(try Self.decode(table.read(length)))
                        }
                        guard table.isAtEnd else { throw UmdError.invalid("Extra chapter titles") }
                    } else {
                        guard let declaredSize else { throw UmdError.invalid("Missing content length") }
                        contents.append(try Self.inflate(payload, maximumSize: min(declaredSize, maximumExpandedSize - (cover?.count ?? 0)) - contents.count))
                    }
                default: break
                }
            } else { throw UmdError.invalid("Invalid marker at byte \(input.position - 1)") }
        }
        guard textBook, ended, declaredSize == contents.count, !titles.isEmpty, titles.count == offsets.count,
              offsets.first == 0, contents.count % 2 == 0 else { throw UmdError.invalid("Incomplete chapter data") }
        for index in offsets.indices {
            guard offsets[index] % 2 == 0, offsets[index] <= contents.count,
                  index == 0 || offsets[index] >= offsets[index - 1] else {
                throw UmdError.invalid("Chapter offset outside content")
            }
        }
        self.title = title; self.author = author; self.kind = kind; self.cover = cover
        self.titles = titles; self.offsets = offsets; self.contents = contents
    }

    public func chapters(bookURL: String) -> [BookChapter] {
        titles.enumerated().map { index, title in
            var chapter = BookChapter()
            chapter.bookUrl = bookURL; chapter.baseUrl = bookURL
            chapter.index = index; chapter.url = String(index); chapter.title = title
            return chapter
        }
    }

    public func content(chapter: BookChapter) throws -> String {
        guard let index = Int(chapter.url ?? ""), offsets.indices.contains(index) else {
            throw UmdError.invalid("Invalid chapter index")
        }
        let end = index + 1 < offsets.count ? offsets[index + 1] : contents.count
        return try Self.decode(contents.subdata(in: offsets[index]..<end)).replacingOccurrences(of: "\u{2029}", with: "\n")
    }

    private static func decode(_ data: Data) throws -> String {
        guard data.count % 2 == 0, let text = String(data: data, encoding: .utf16LittleEndian) else {
            throw UmdError.invalid("Invalid UTF-16LE text")
        }
        return text
    }

    private static func inflate(_ data: Data, maximumSize: Int) throws -> Data {
        guard maximumSize >= 0, !data.isEmpty, data.count <= Int(UInt32.max) else {
            throw UmdError.invalid("Invalid compressed content length")
        }
        return try data.withUnsafeBytes { input in
            var stream = z_stream()
            guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw UmdError.invalid("Unable to initialize zlib")
            }
            defer { inflateEnd(&stream) }
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress!)
            stream.avail_in = uInt(data.count)
            var result = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                try Task.checkCancellation()
                let previous = stream.avail_in
                let status = buffer.withUnsafeMutableBufferPointer { output in
                    stream.next_out = output.baseAddress
                    stream.avail_out = uInt(output.count)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
                let count = buffer.count - Int(stream.avail_out)
                guard count <= maximumSize - result.count else { throw UmdError.invalid("Content exceeds expansion limit") }
                result.append(contentsOf: buffer.prefix(count))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else { throw UmdError.invalid("Trailing compressed bytes") }
                    return result
                }
                guard status == Z_OK, count > 0 || stream.avail_in < previous else {
                    throw UmdError.invalid("Corrupt or truncated zlib content")
                }
            }
        }
    }

    private struct Cursor {
        let data: Data
        var position = 0
        var isAtEnd: Bool { position == data.count }
        mutating func read(_ count: Int) throws -> Data {
            guard count >= 0, count <= data.count - position else {
                throw UmdError.invalid("Truncated section at byte \(position)")
            }
            defer { position += count }
            return data.subdata(in: position..<(position + count))
        }
        mutating func number(_ count: Int) throws -> Int {
            try read(count).enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
        }
    }
}
