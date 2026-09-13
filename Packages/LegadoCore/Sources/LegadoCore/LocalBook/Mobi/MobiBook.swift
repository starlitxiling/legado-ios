import Foundation
import SwiftSoup

public final class MobiBook {
    public struct Section {
        public let title: String
        let ranges: [Range<Int>]
        let records: MobiTextRecords
        let encoding: String.Encoding
        public var html: String {
            get throws {
                let data = try records.read(ranges)
                return try MobiBytes(data).string(0, data.count, encoding)
            }
        }
    }
    public struct DirectoryNode {
        public let title: String
        public let isVolume: Bool
        public let sectionIndex: Int?
    }
    private struct Cut {
        var offset: Int
        let title: String
        var isVolume = false
        var reference: String? = nil
    }
    struct IndexEntry { let label: String; let tags: [Int: [Int]] }
    struct IndexData { let table: [IndexEntry]; let cncx: [Int: String] }
    private let pdb: PdbReader
    public let header: MobiHeader
    private let boundary: Int
    private let resourceStart: Int
    public private(set) var sections: [Section] = []
    public private(set) var directory: [DirectoryNode] = []
    private var raw = Data()
    private var records: MobiTextRecords!
    public let cacheCost: Int

    public init(data: Data, onRecordDecoded: ((Int) -> Void)? = nil) throws {
        cacheCost = data.count
        pdb = try PdbReader(data: data)
        let first = try MobiHeader(data: pdb.getRecordData(0))
        resourceStart = first.resourceStart
        if first.version < 8, let offset = first.boundary {
            header = try MobiHeader(data: pdb.getRecordData(offset)); boundary = offset
        } else { header = first; boundary = 0 }
        guard header.numTextRecords > 0, header.numTextRecords < pdb.recordCount - boundary else {
            throw MobiError.invalid("正文记录数量无效")
        }
        var decoder: HuffCdicDecoder?
        if header.compression == 17480 {
            guard header.numHuffcdic > 1, header.numHuffcdic <= pdb.recordCount else { throw MobiError.invalid("HUFF 记录数量无效") }
            decoder = try HuffCdicDecoder(records: (0..<header.numHuffcdic).map { try getRecord(header.huffcdic + $0) })
        }
        records = MobiTextRecords(pdb: pdb, header: header, boundary: boundary, decoder: decoder, onRecordDecoded: onRecordDecoded)
        raw = try records.buildTextRecordOffsets()
        sections = try header.version >= 8 ? processKF8Sections() : processSections()
        raw = Data()
        guard !sections.isEmpty else { throw MobiError.invalid("没有正文") }
    }

    public func getRecord(_ index: Int) throws -> Data {
        guard index >= 0, index < pdb.recordCount - boundary else { throw MobiError.invalid("记录编号越界") }
        return try pdb.getRecordData(boundary + index)
    }
    public func getResource(_ index: Int) throws -> Data {
        guard index >= 0, resourceStart < pdb.recordCount, index < pdb.recordCount - resourceStart else {
            throw MobiError.invalid("图片记录不存在")
        }
        return try pdb.getRecordData(resourceStart + index)
    }
    public func getCover() throws -> Data? { try header.coverOffset.map { try getResource($0) } }
    public func getResourceByHref(_ href: String) throws -> Data? {
        if href.hasPrefix("recindex:"), let index = Int(href.dropFirst(9)), index > 0 { return try getResource(index - 1) }
        if href.hasPrefix("kindle:embed:") {
            if let value = href.dropFirst(13).split(separator: "?").first,
               let index = Int(value, radix: 32), index > 0 { return try getResource(index - 1) }
        }
        return nil
    }
    public func getTextRecord(_ index: Int) throws -> Data {
        try records.getTextRecord(index)
    }

    func getIndexData(_ index: Int) throws -> IndexData {
        let root = MobiBytes(try getRecord(index))
        guard try root.string(0, 4) == "INDX" else { throw MobiError.invalid("INDX 标识无效") }
        let length = try root.uint(4), count = try root.uint(24), cncxCount = try root.uint(52)
        guard count <= pdb.recordCount, cncxCount <= pdb.recordCount else { throw MobiError.invalid("索引记录数量无效") }
        guard try root.string(length, 4) == "TAGX" else { throw MobiError.invalid("TAGX 标识无效") }
        let tagLength = try root.uint(length + 4), controls = try root.uint(length + 8)
        guard tagLength >= 12, controls > 0 else { throw MobiError.invalid("TAGX 长度无效") }
        _ = try root.bytes(length, tagLength)
        var tags: [(id: Int, values: Int, mask: Int, end: Int)] = []
        for offset in stride(from: length + 12, to: length + tagLength, by: 4) {
            tags.append((try root.uint(offset, 1), try root.uint(offset + 1, 1), try root.uint(offset + 2, 1), try root.uint(offset + 3, 1)))
        }
        var cncx: [Int: String] = [:]
        for number in 0..<cncxCount {
            let b = MobiBytes(try getRecord(index + count + number + 1))
            var pos = 0
            while pos < b.data.count {
                let start = pos, size = try b.variable(&pos)
                cncx[number * 65536 + start] = try b.string(pos, size, header.encoding); pos += size
            }
        }
        var table: [IndexEntry] = []
        for number in 0..<count {
            let b = MobiBytes(try getRecord(index + number + 1))
            guard try b.string(0, 4) == "INDX" else { throw MobiError.invalid("INDX 数据无效") }
            let idxt = try b.uint(20), entries = try b.uint(24)
            guard try b.string(idxt, 4) == "IDXT", entries <= b.data.count / 2 else { throw MobiError.invalid("IDXT 无效") }
            for item in 0..<entries {
                let offset = try b.uint(idxt + 4 + item * 2, 2), size = try b.uint(offset, 1)
                let label = try b.string(offset + 1, size, header.encoding)
                let start = offset + 1 + size
                var pos = start + controls, control = 0
                var pending: [(Int, Int, Int? , Int?)] = []
                for tag in tags {
                    if tag.end == 1 { control += 1; continue }
                    guard tag.mask > 0, control < controls else { throw MobiError.invalid("TAGX 掩码无效") }
                    let value = try b.uint(start + control, 1) & tag.mask
                    if value == tag.mask && tag.mask.nonzeroBitCount > 1 {
                        pending.append((tag.id, tag.values, nil, try b.variable(&pos)))
                    } else {
                        pending.append((tag.id, tag.values, value >> tag.mask.trailingZeroBitCount, nil))
                    }
                }
                var values: [Int: [Int]] = [:]
                for (id, width, number, bytes) in pending {
                    var list: [Int] = []
                    if let number {
                        guard number * width <= b.data.count else { throw MobiError.invalid("索引值数量无效") }
                        for _ in 0..<(number * width) { list.append(try b.variable(&pos)) }
                    } else if let bytes {
                        let end = pos + bytes
                        guard end <= b.data.count else { throw MobiError.invalid("索引值越界") }
                        while pos < end { list.append(try b.variable(&pos)) }
                        guard pos == end else { throw MobiError.invalid("索引值长度无效") }
                    }
                    values[id] = list
                }
                table.append(IndexEntry(label: label, tags: values))
            }
        }
        return IndexData(table: table, cncx: cncx)
    }

    private func orderedNCX(_ index: IndexData) throws -> [(entry: IndexEntry, isVolume: Bool)] {
        var children: [Int: [Int]] = [:]
        for (number, entry) in index.table.enumerated() {
            if let parent = entry.tags[21]?.first, index.table.indices.contains(parent), parent != number {
                children[parent, default: []].append(number)
            }
        }
        var visited = Set<Int>(), active = Set<Int>()
        var result: [(IndexEntry, Bool)] = []
        func visit(_ number: Int) throws {
            guard !active.contains(number) else { throw MobiError.invalid("NCX 目录循环引用") }
            if visited.contains(number) { return }
            active.insert(number); visited.insert(number)
            let entry = index.table[number], descendants = children[number] ?? []
            result.append((entry, !descendants.isEmpty))
            for child in descendants { try visit(child) }
            active.remove(number)
        }
        for (number, entry) in index.table.enumerated() {
            let parent = entry.tags[21]?.first
            if entry.tags[4]?.first == 0 || parent == nil || !index.table.indices.contains(parent!) {
                try visit(number)
            }
        }
        for number in index.table.indices where !visited.contains(number) { try visit(number) }
        return result
    }

    private func appendNodes(_ cuts: [Cut], extent: Int, result: inout [Section], ranges: (Int, Int) -> [Range<Int>]) throws {
        let starts = Array(Set(cuts.map(\.offset))).sorted()
        let ends = Dictionary(uniqueKeysWithValues: starts.enumerated().map { ($0.element, $0.offset + 1 < starts.count ? starts[$0.offset + 1] : extent) })
        for (index, cut) in cuts.enumerated() {
            guard cut.offset >= 0, cut.offset < extent else { throw MobiError.invalid("目录偏移越界") }
            if cut.isVolume, index + 1 < cuts.count, cuts[index + 1].reference == cut.reference {
                directory.append(DirectoryNode(title: cut.title, isVolume: true, sectionIndex: nil))
                continue
            }
            let end = ends[cut.offset] ?? extent
            let spans = ranges(cut.offset, end)
            var title = cut.title
            if title.isEmpty {
                let first = spans.first ?? 0..<0
                let html = try MobiBytes(raw).string(first.lowerBound, first.count, header.encoding)
                title = try sectionTitle(html, index: directory.count)
            }
            directory.append(DirectoryNode(title: title, isVolume: cut.isVolume, sectionIndex: result.count))
            result.append(Section(title: title, ranges: spans, records: records, encoding: header.encoding))
        }
    }

    private func processSections() throws -> [Section] {
        let bytes = MobiBytes(raw)
        let byteText = String(data: raw, encoding: .isoLatin1)!
        let regex = try NSRegularExpression(pattern: "(?i)<\\s*(?:mbp:)?pagebreak[^>]*>")
        var pages: [Range<Int>] = [], start = 0
        for match in regex.matches(in: byteText, range: NSRange(location: 0, length: raw.count)) {
            pages.append(start..<match.range.location)
            start = NSMaxRange(match.range)
        }
        if start < raw.count { pages.append(start..<raw.count) }
        var cuts: [Cut] = []
        if header.indx != 0xffffffff {
            let index = try getIndexData(header.indx)
            for node in try orderedNCX(index) {
                if let offset = node.entry.tags[1]?.first, let label = node.entry.tags[3]?.first {
                    cuts.append(Cut(offset: offset, title: index.cncx[label] ?? "", isVolume: node.isVolume, reference: "filepos:\(offset)"))
                }
            }
        }
        if cuts.isEmpty {
            let doc = try SwiftSoup.parse(bytes.string(0, raw.count, header.encoding))
            var navigation = doc
            if let guide = try doc.select("guide reference[type=toc][filepos]").first(),
               let offset = Int(try guide.attr("filepos")) {
                guard offset >= 0, offset < raw.count else { throw MobiError.invalid("guide 目录偏移越界") }
                let remaining = try bytes.bytes(offset, raw.count - offset)
                let text = String(data: remaining, encoding: .isoLatin1)!
                let end = regex.firstMatch(in: text, range: NSRange(location: 0, length: remaining.count))?.range.location ?? remaining.count
                navigation = try SwiftSoup.parse(bytes.string(offset, end, header.encoding))
            }
            for anchor in try navigation.select("a[filepos]") {
                if let offset = Int(try anchor.attr("filepos")) { cuts.append(Cut(offset: offset, title: try anchor.text())) }
            }
        }
        if cuts.isEmpty {
            cuts = pages.filter { !$0.isEmpty }.map { Cut(offset: $0.lowerBound, title: "") }
        } else {
            for index in cuts.indices {
                guard cuts[index].offset >= 0, let page = pages.first(where: { $0.upperBound > cuts[index].offset }) else {
                    throw MobiError.invalid("目录偏移越界")
                }
                cuts[index].offset = page.lowerBound
            }
            if !cuts.contains(where: { $0.offset == 0 }) { cuts.insert(Cut(offset: 0, title: "卷首"), at: 0) }
        }
        var result: [Section] = []
        try appendNodes(cuts, extent: raw.count, result: &result) { start, end in
            pages.compactMap { page in
                let lower = max(start, page.lowerBound), upper = min(end, page.upperBound)
                return lower < upper ? lower..<upper : nil
            }
        }
        return result
    }

    private func sectionTitle(_ html: String, index: Int) throws -> String {
        let doc = try SwiftSoup.parse(html)
        let title = try doc.select("h1, h2, h3, title").first()?.text() ?? ""
        return title.isEmpty ? "第 \(index + 1) 章" : title
    }

    // A reconstructed KF8 section is represented by source spans, so chapter reads need no other fragments.
    private func slice(_ spans: [Range<Int>], from start: Int, to end: Int) -> [Range<Int>] {
        var position = 0, result: [Range<Int>] = []
        for span in spans {
            let lower = max(start, position), upper = min(end, position + span.count)
            if lower < upper { result.append((span.lowerBound + lower - position)..<(span.lowerBound + upper - position)) }
            position += span.count
        }
        return result
    }

    private func processKF8Sections() throws -> [Section] {
        let skeletons = try getIndexData(header.skel).table
        let fragments = try getIndexData(header.frag).table
        let ncx = header.indx != 0xffffffff ? try getIndexData(header.indx) : nil
        var references: [(fid: Int, offset: Int, title: String, isVolume: Bool)] = []
        if let ncx {
            for node in try orderedNCX(ncx) {
                if let position = node.entry.tags[6], position.count >= 2, let label = node.entry.tags[3]?.first {
                    references.append((position[0], position[1], ncx.cncx[label] ?? "", node.isVolume))
                }
            }
        }
        if references.isEmpty, header.guide != 0xffffffff {
            let guide = try getIndexData(header.guide)
            for entry in guide.table {
                if let position = entry.tags[6], let fid = position.first, let label = entry.tags[1]?.first {
                    references.append((fid, position.count > 1 ? position[1] : 0, guide.cncx[label] ?? "", false))
                }
            }
        }
        var nextFragment = 0, result: [Section] = []
        for skeleton in skeletons {
            guard let count = skeleton.tags[1]?.first, let range = skeleton.tags[6], range.count >= 2,
                  count >= 0, count <= fragments.count - nextFragment else { throw MobiError.invalid("KF8 骨架索引无效") }
            let start = range[0], length = range[1]
            _ = try MobiBytes(raw).bytes(start, length)
            var spans = [start..<(start + length)], total = length
            var positions: [Int: (offset: Int, length: Int)] = [:]
            for fid in nextFragment..<(nextFragment + count) {
                let fragment = fragments[fid]
                guard let insertion = Int(fragment.label), let value = fragment.tags[6], value.count >= 2 else {
                    throw MobiError.invalid("KF8 片段索引无效")
                }
                let offset = insertion - start, source = start + length + value[0]
                guard offset >= 0, offset <= total else { throw MobiError.invalid("KF8 插入位置越界") }
                _ = try MobiBytes(raw).bytes(source, value[1])
                for (key, position) in positions where position.offset >= offset {
                    positions[key] = (position.offset + value[1], position.length)
                }
                spans = slice(spans, from: 0, to: offset) + [source..<(source + value[1])] + slice(spans, from: offset, to: total)
                total += value[1]
                positions[fid] = (offset, value[1])
            }
            nextFragment += count
            var cuts: [Cut] = []
            for reference in references {
                guard let position = positions[reference.fid] else { continue }
                guard reference.offset >= 0, reference.offset < position.length else { throw MobiError.invalid("KF8 目录偏移越界") }
                cuts.append(Cut(offset: position.offset + reference.offset, title: reference.title, isVolume: reference.isVolume, reference: "\(reference.fid):\(reference.offset)"))
            }
            if let first = cuts.first, first.offset > 0 {
                let prefixSpans = slice(spans, from: 0, to: first.offset)
                let data = prefixSpans.reduce(into: Data()) { $0.append(raw[$1]) }
                let prefix = try MobiBytes(data).string(0, data.count, header.encoding)
                if try SwiftSoup.parse(prefix).text().isEmpty {
                    for index in cuts.indices where cuts[index].offset == first.offset { cuts[index].offset = 0 }
                } else { cuts.insert(Cut(offset: 0, title: "卷首"), at: 0) }
            }
            if cuts.isEmpty { cuts = [Cut(offset: 0, title: "")] }
            try appendNodes(cuts, extent: total, result: &result) { start, end in
                slice(spans, from: start, to: end)
            }
        }
        return result
    }
}
