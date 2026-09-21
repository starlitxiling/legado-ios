import Foundation

public final class QueryTTF: @unchecked Sendable {
    public let unicodeToGlyphId: [Int: Int]
    public let unicodeToGlyph: [Int: String]
    public let glyphToUnicode: [String: Int]
    private let glyphs: [String?]

    public init(_ data: Data) throws {
        let bytes = Array(data)
        var reader = FontReader(bytes: bytes, position: 0, end: bytes.count)
        _ = try reader.uint(4)
        let count = try reader.uint(2)
        try reader.skip(6)
        var tables: [String: Range<Int>] = [:]
        for _ in 0..<count {
            let tag = try reader.take(4)
            _ = try reader.uint(4)
            let offset = try reader.uint(4), length = try reader.uint(4)
            guard offset <= bytes.count, length <= bytes.count - offset else { throw Self.invalid("table bounds") }
            tables[String(bytes: tag, encoding: .ascii) ?? ""] = offset..<(offset + length)
        }
        func table(_ name: String) throws -> FontReader {
            guard let range = tables[name] else { throw Self.invalid("missing " + name + " table") }
            return FontReader(bytes: bytes, position: range.lowerBound, end: range.upperBound)
        }
        var head = try table("head"); try head.skip(50)
        let locationFormat = try head.uint(2)
        guard locationFormat <= 1 else { throw Self.invalid("loca format") }
        var maxp = try table("maxp"); try maxp.skip(4)
        let glyphCount = try maxp.uint(2)
        try maxp.skip(2)
        let maxContours = try maxp.uint(2)
        var loca = try table("loca")
        var offsets: [Int] = []
        for _ in 0...glyphCount { offsets.append(try loca.uint(locationFormat == 0 ? 2 : 4) * (locationFormat == 0 ? 2 : 1)) }
        let glyf = try table("glyf")
        var glyphs = [String?](repeating: nil, count: glyphCount)
        for index in 0..<glyphCount {
            let start = offsets[index], end = offsets[index + 1]
            guard start <= end, end <= glyf.end - glyf.position else { throw Self.invalid("glyph bounds") }
            if start == end { continue }
            var glyph = FontReader(bytes: bytes, position: glyf.position + start, end: glyf.position + end)
            let contours = try glyph.sint(2)
            try glyph.skip(8)
            if contours == 0 || contours > maxContours { continue }
            if contours > 0 {
                var points = 0
                for _ in 0..<contours { points = try glyph.uint(2) + 1 }
                let instructions = try glyph.uint(2); try glyph.skip(instructions)
                var flags: [Int] = []
                while flags.count < points {
                    let flag = try glyph.uint(1), repeats = flag & 8 == 0 ? 0 : try glyph.uint(1)
                    guard repeats < points - flags.count else { throw Self.invalid("glyph flag repetition") }
                    flags += Array(repeating: flag, count: repeats + 1)
                }
                func coordinates(_ short: Int, _ same: Int, _ reader: inout FontReader) throws -> [Int] {
                    try flags.map { flag in
                        if flag & short != 0 { return try reader.uint(1) * (flag & same == 0 ? -1 : 1) }
                        return flag & same != 0 ? 0 : try reader.sint(2)
                    }
                }
                let x = try coordinates(2,16,&glyph), y = try coordinates(4,32,&glyph)
                glyphs[index] = zip(x,y).map { "\($0),\($1)" }.joined(separator: "|")
            } else {
                var components: [String] = []
                while true {
                    let flags = try glyph.uint(2), id = try glyph.uint(2), size = flags & 1 == 0 ? 1 : 2
                    let a = try flags & 2 == 0 ? glyph.uint(size) : glyph.sint(size)
                    let b = try flags & 2 == 0 ? glyph.uint(size) : glyph.sint(size)
                    var x: Float = 0, y: Float = 0, xy: Float = 0, yx: Float = 0
                    switch flags & 0xc8 {
                    case 8: x = Float(try glyph.uint(2)) / 16384; y = x
                    case 64: x = Float(try glyph.uint(2)) / 16384; y = Float(try glyph.uint(2)) / 16384
                    case 128:
                        x = Float(try glyph.uint(2)) / 16384; xy = Float(try glyph.uint(2)) / 16384
                        yx = Float(try glyph.uint(2)) / 16384; y = Float(try glyph.uint(2)) / 16384
                    default: break
                    }
                    components.append("{flags:\(flags),glyphIndex:\(id),arg1:\(a),arg2:\(b),xScale:\(x),scale01:\(xy),scale10:\(yx),yScale:\(y)}")
                    if flags & 32 == 0 { break }
                }
                glyphs[index] = "[" + components.joined(separator: ",") + "]"
            }
        }
        var cmap = try table("cmap")
        let cmapStart = cmap.position
        try cmap.skip(2)
        let records = try cmap.uint(2)
        var subtableOffsets: [Int] = []
        for _ in 0..<records { try cmap.skip(4); subtableOffsets.append(try cmap.uint(4)) }
        var ids: [Int: Int] = [:], seen = Set<Int>()
        for offset in subtableOffsets where seen.insert(offset).inserted {
            guard offset <= cmap.end - cmapStart else { throw Self.invalid("cmap offset") }
            var sub = FontReader(bytes: bytes, position: cmapStart + offset, end: cmap.end)
            let format = try sub.uint(2)
            if ![0,4,6].contains(format) { continue }
            let length = try sub.uint(2)
            guard length >= 6, length <= cmap.end - cmapStart - offset else { throw Self.invalid("cmap length") }
            sub.end = cmapStart + offset + length
            try sub.skip(2)
            if format == 0 {
                for code in 0..<(length - 6) { let id = try sub.uint(1); if id != 0 { ids[code] = id } }
            } else if format == 6 {
                let first = try sub.uint(2), count = try sub.uint(2)
                for index in 0..<count { ids[first + index] = try sub.uint(2) }
            } else {
                let count = try sub.uint(2) / 2
                try sub.skip(6)
                let ends = try (0..<count).map { _ in try sub.uint(2) }
                try sub.skip(2)
                let starts = try (0..<count).map { _ in try sub.uint(2) }
                let deltas = try (0..<count).map { _ in try sub.sint(2) }
                let ranges = try (0..<count).map { _ in try sub.uint(2) }
                let arrayCount = (sub.end - sub.position) / 2
                let array = try (0..<arrayCount).map { _ in try sub.uint(2) }
                for index in 0..<count {
                    guard starts[index] <= ends[index] else { throw Self.invalid("cmap segment") }
                    for code in starts[index]...ends[index] {
                        let id: Int
                        if ranges[index] == 0 { id = (code + deltas[index]) & 0xffff }
                        else {
                            let slot = ranges[index] / 2 + code - starts[index] + index - count
                            id = array.indices.contains(slot) ? array[slot] + deltas[index] : 0
                        }
                        if id != 0 { ids[code] = id }
                    }
                }
            }
        }
        var forward: [Int: String] = [:], reverse: [String: Int] = [:]
        for code in ids.keys.sorted() {
            guard let id = ids[code], glyphs.indices.contains(id), let glyph = glyphs[id] else { continue }
            forward[code] = glyph; reverse[glyph] = code
        }
        self.glyphs = glyphs; unicodeToGlyphId = ids; unicodeToGlyph = forward; glyphToUnicode = reverse
    }

    public func getGlyfById(_ id: Int) -> String? { glyphs.indices.contains(id) ? glyphs[id] : nil }
    public func getGlyfIdByUnicode(_ unicode: Int) -> Int { unicodeToGlyphId[unicode] ?? 0 }
    public func getGlyfByUnicode(_ unicode: Int) -> String? { unicodeToGlyph[unicode] }
    public func getUnicodeByGlyf(_ glyph: String?) -> Int { glyph.flatMap { glyphToUnicode[$0] } ?? 0 }
    public func isBlankUnicode(_ unicode: Int) -> Bool { [9,32,160,0x2002,0x2003,0x2007,0x200a,0x200b,0x200c,0x200d,0x202f,0x205f].contains(unicode) }

    static func invalid(_ detail: String) -> JsEngineError { .exception("queryTTF invalid font: " + detail) }
}

private struct FontReader {
    let bytes: [UInt8]
    var position: Int
    var end: Int
    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, position >= 0, position <= end, count <= end - position else { throw QueryTTF.invalid("truncated data at \(position)") }
        defer { position += count }
        return bytes[position..<(position + count)]
    }
    mutating func uint(_ size: Int) throws -> Int { try take(size).reduce(0) { ($0 << 8) | Int($1) } }
    mutating func sint(_ size: Int) throws -> Int { let n = try uint(size); return n & (1 << (size * 8 - 1)) == 0 ? n : n - (1 << (size * 8)) }
    mutating func skip(_ count: Int) throws { _ = try take(count) }
}
