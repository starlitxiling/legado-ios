import XCTest
@testable import LegadoCore

final class MobiBinaryTests: XCTestCase {
    private func put(_ data: inout Data, _ offset: Int, _ value: Int, _ size: Int = 4) {
        for index in 0..<size { data[offset + index] = UInt8(truncatingIfNeeded: value >> ((size - index - 1) * 8)) }
    }
    private func pdb(_ records: [Data]) -> Data {
        var data = Data(repeating: 0, count: 78 + records.count * 8 + 2)
        data.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
        put(&data, 76, records.count, 2)
        var offset = data.count
        for (index, record) in records.enumerated() { put(&data, 78 + index * 8, offset); offset += record.count }
        for record in records { data.append(record) }
        return data
    }
    func testHuffLiteralDictionaryAndCycle() throws {
        var huff = Data(repeating: 0, count: 1304)
        huff.replaceSubrange(0..<4, with: Data("HUFF".utf8))
        put(&huff, 8, 24); put(&huff, 12, 1048)
        for index in 0..<256 { put(&huff, 24 + index * 4, (index << 8) | 0x88) }
        var cdic = Data(repeating: 0, count: 21)
        cdic.replaceSubrange(0..<4, with: Data("CDIC".utf8))
        put(&cdic, 4, 16); put(&cdic, 8, 1); put(&cdic, 12, 0)
        put(&cdic, 16, 2, 2); put(&cdic, 18, 0x8001, 2); cdic[20] = 90
        XCTAssertEqual(try HuffCdicDecoder(records: [huff, cdic]).decompress(Data([0, 255])), Data("ZZ".utf8))
        XCTAssertThrowsError(try HuffCdicDecoder(records: [huff, cdic]).decompress(Data([0, 255]), limit: 1))
        put(&cdic, 18, 1, 2); cdic[20] = 0
        XCTAssertThrowsError(try HuffCdicDecoder(records: [huff, cdic]).decompress(Data([0])))
        XCTAssertThrowsError(try HuffCdicDecoder(records: [Data("HUFF".utf8)]))
    }
    func testCP1252AndCoverRecordWithoutPagebreaks() throws {
        let original = try PdbReader(data: MobiPdfTests.mobi())
        var header = try original.getRecordData(0)
        let text = Data([60,112,62,99,97,102,233,60,47,112,62])
        put(&header, 0, 1, 2); put(&header, 4, text.count); put(&header, 28, 1252)
        put(&header, 128, 0); put(&header, 108, 2)
        let book = try MobiBook(data: pdb([header, text, Data([1, 2, 3])]))
        XCTAssertEqual(book.sections.count, 1)
        XCTAssertTrue(try book.sections[0].html.contains("café"))
        XCTAssertEqual(try book.getResourceByHref("recindex:1"), Data([1, 2, 3]))
        XCTAssertNil(try book.getResourceByHref("kindle:embed:"))
        XCTAssertNil(try book.getResourceByHref("recindex:0"))
        XCTAssertThrowsError(try book.getResource(Int.max))
        XCTAssertThrowsError(try book.getRecord(Int.max))
    }
    func testMalformedPdbOffsetsAndEncryptedHeader() throws {
        var bytes = MobiPdfTests.mobi()
        put(&bytes, 78, Int(UInt32.max))
        XCTAssertThrowsError(try PdbReader(data: bytes))
        var header = try PdbReader(data: MobiPdfTests.mobi()).getRecordData(0)
        put(&header, 12, 1, 2)
        XCTAssertThrowsError(try MobiHeader(data: header))
        for count in 0..<78 { XCTAssertThrowsError(try PdbReader(data: Data(repeating: 0, count: count))) }
    }

    private func variable(_ value: Int) -> Data {
        var value = value, bytes = [UInt8(value & 127) | 128]
        value >>= 7
        while value > 0 { bytes.insert(UInt8(value & 127), at: 0); value >>= 7 }
        return Data(bytes)
    }
    private func index(tags: [(Int, Int)], entries: [(String, [Int])], cncx: Bool = false, masks: [UInt8]? = nil) -> [Data] {
        var root = Data(repeating: 0, count: 68 + tags.count * 4)
        root.replaceSubrange(0..<4, with: Data("INDX".utf8)); put(&root, 4, 56); put(&root, 24, 1); put(&root, 52, cncx ? 1 : 0)
        root.replaceSubrange(56..<60, with: Data("TAGX".utf8)); put(&root, 60, 12 + tags.count * 4); put(&root, 64, 1)
        for (i, tag) in tags.enumerated() {
            root[68 + i * 4] = UInt8(tag.0); root[69 + i * 4] = UInt8(tag.1); root[70 + i * 4] = UInt8(1 << i)
        }
        var record = Data(repeating: 0, count: 56), offsets: [Int] = []
        record.replaceSubrange(0..<4, with: Data("INDX".utf8)); put(&record, 24, entries.count)
        for (entryIndex, entry) in entries.enumerated() {
            let (label, values) = entry
            offsets.append(record.count); record.append(UInt8(label.utf8.count)); record.append(Data(label.utf8))
            record.append(masks?[entryIndex] ?? UInt8((1 << tags.count) - 1))
            for value in values { record.append(variable(value)) }
        }
        put(&record, 20, record.count); record.append(Data("IDXT".utf8))
        for offset in offsets { record.append(UInt8(offset >> 8)); record.append(UInt8(offset & 255)) }
        return [root, record]
    }
    func testKF8RebuildAndTwoNCXChaptersInsideOneSkeleton() throws {
        let skeleton = Data("<body></body>".utf8)
        let first = Data("<h1>One</h1><p>Alpha</p>".utf8), second = Data("<h1>Two</h1><p>Beta</p>".utf8)
        let raw = skeleton + first + second
        var header = try PdbReader(data: MobiPdfTests.mobi()).getRecordData(0)
        put(&header, 0, 1, 2); put(&header, 4, raw.count); put(&header, 36, 8)
        put(&header, 248, 4); put(&header, 252, 2); put(&header, 244, 6); put(&header, 260, 0xffffffff)
        var records = [header, raw]
        records += index(tags: [(1, 1), (6, 2)], entries: [("skeleton", [2, 0, skeleton.count])])
        records += index(tags: [(6, 2)], entries: [("6", [0, first.count]), (String(6 + first.count), [first.count, second.count])])
        records += index(tags: [(3, 1), (6, 2)], entries: [("0", [0, 0, 0]), ("1", [4, 1, 0])], cncx: true)
        records.append(variable(3) + Data("One".utf8) + variable(3) + Data("Two".utf8))
        let book = try MobiBook(data: pdb(records))
        XCTAssertEqual(book.sections.map(\.title), ["One", "Two"])
        guard book.sections.count == 2 else { return }
        XCTAssertTrue(try book.sections[0].html.contains("Alpha"))
        XCTAssertFalse(try book.sections[0].html.contains("Beta"))
        XCTAssertTrue(try book.sections[1].html.contains("Beta"))
    }

    func testKF7NCXByteOffsetsAndEXTHCover() throws {
        let first = Data("<h1>第一章</h1><p>Alpha</p>".utf8), second = Data("<h1>第二章</h1><p>Beta</p>".utf8)
        let pagebreak = Data("<mbp:pagebreak/>".utf8)
        let raw = first + pagebreak + second
        var header = try PdbReader(data: MobiPdfTests.mobi()).getRecordData(0)
        put(&header, 0, 1, 2); put(&header, 4, raw.count); put(&header, 244, 2); put(&header, 108, 5)
        let exthSize = header.count - 264
        put(&header, 268, exthSize + 12); put(&header, 272, 3)
        let offset = header.count
        header.append(Data(repeating: 0, count: 12)); put(&header, offset, 201); put(&header, offset + 4, 12)
        var records = [header, raw]
        records += index(tags: [(1, 1), (3, 1)], entries: [("0", [0, 0]), ("1", [first.count + pagebreak.count, 4])], cncx: true)
        records.append(variable(3) + Data("One".utf8) + variable(3) + Data("Two".utf8))
        records.append(Data([0xff, 0xd8, 0xff, 0xd9]))
        let book = try MobiBook(data: pdb(records))
        XCTAssertEqual(book.sections.map(\.title), ["One", "Two"])
        XCTAssertTrue(try book.sections[0].html.contains("第一章"))
        XCTAssertFalse(try book.sections[0].html.contains("Beta"))
        XCTAssertEqual(try book.getCover(), records.last)
    }

    func testGuideDirectoryExcludesBodyCrossReferences() throws {
        var html = "<html><guide><reference type='toc' filepos='0000000001'/></guide><body><!--toc--><a filepos='0000000002'>One</a><a filepos='0000000003'>Two</a><mbp:pagebreak/><!--one--><h1>One</h1><p>Alpha<!--xref-->details</p><mbp:pagebreak/><!--two--><h1>Two</h1><a filepos='0000000004'>Cross reference</a></body></html>"
        let original = Data(html.utf8)
        for (index, marker) in ["<!--toc-->", "<!--one-->", "<!--two-->", "<!--xref-->"].enumerated() {
            let offset = try XCTUnwrap(original.range(of: Data(marker.utf8))).lowerBound
            html = html.replacingOccurrences(of: String(format: "%010d", index + 1), with: String(format: "%010d", offset))
        }
        let raw = Data(html.utf8)
        var header = try PdbReader(data: MobiPdfTests.mobi()).getRecordData(0)
        put(&header, 0, 1, 2); put(&header, 4, raw.count)
        let book = try MobiBook(data: pdb([header, raw]))
        XCTAssertEqual(book.sections.map(\.title), ["卷首", "One", "Two"])
    }

    func testNCXVolumeAndFirstChapterAtSamePosition() throws {
        for kf8 in [false, true] {
            let text = Data("<h1>One</h1><p>Alpha</p>".utf8)
            let skeleton = Data("<body></body>".utf8)
            let raw = kf8 ? skeleton + text : text
            var header = try PdbReader(data: MobiPdfTests.mobi()).getRecordData(0)
            put(&header, 0, 1, 2); put(&header, 4, raw.count)
            put(&header, 244, kf8 ? 6 : 2)
            var records = [header, raw]
            if kf8 {
                put(&header, 36, 8); put(&header, 248, 4); put(&header, 252, 2); put(&header, 260, 0xffffffff)
                records[0] = header
                records += index(tags: [(1, 1), (6, 2)], entries: [("skeleton", [1, 0, skeleton.count])])
                records += index(tags: [(6, 2)], entries: [("6", [0, text.count])])
            }
            let position = kf8 ? [0, 0] : [0]
            records += index(tags: [(kf8 ? 6 : 1, kf8 ? 2 : 1), (3, 1), (4, 1), (21, 1), (22, 1)],
                entries: [("volume", position + [0, 0, 1]), ("chapter", position + [7, 1, 0])], cncx: true, masks: [23, 15])
            records.append(variable(6) + Data("Volume".utf8) + variable(3) + Data("One".utf8))
            let url = try file(pdb(records))
            let decodedBook = try MobiBook(data: pdb(records))
            XCTAssertEqual(decodedBook.directory.count, 2)
            XCTAssertEqual(decodedBook.sections.count, 1)
            let parsed = try LocalBook.parse(url: url)
            XCTAssertEqual(parsed.chapters.map(\.title), ["Volume", "One"], "KF8=\(kf8)")
            guard parsed.chapters.count == 2 else { continue }
            XCTAssertEqual(parsed.chapters.map(\.isVolume), [true, false])
            XCTAssertEqual(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[0]), "")
            XCTAssertTrue(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[1]).contains("Alpha"))
        }
    }

    private func file(_ data: Data) throws -> URL {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/tmp")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString + ".mobi")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testKF7NCXAnchorsMapToPagebreakSections() throws {
        let first = Data("<h1>One</h1><p>FIRST_START Alpha</p>".utf8)
        let pagebreak = Data("<mbp:pagebreak/>".utf8)
        let second = Data("<h1>Two</h1><p>SECOND_START Beta</p>".utf8)
        let raw = first + pagebreak + second
        var header = try PdbReader(data: MobiPdfTests.mobi()).getRecordData(0)
        put(&header, 0, 1, 2); put(&header, 4, raw.count); put(&header, 244, 2)
        let firstAnchor = try XCTUnwrap(raw.range(of: Data("Alpha".utf8))).lowerBound
        let secondAnchor = try XCTUnwrap(raw.range(of: Data("Beta".utf8))).lowerBound
        var records = [header, raw]
        records += index(tags: [(1, 1), (3, 1)], entries: [("0", [firstAnchor, 0]), ("1", [secondAnchor, 4])], cncx: true)
        records.append(variable(3) + Data("One".utf8) + variable(3) + Data("Two".utf8))
        let parsed = try LocalBook.parse(url: file(pdb(records)))
        XCTAssertEqual(parsed.chapters.map(\.title), ["One", "Two"])
        let one = try XCTUnwrap(parsed.chapters.first { $0.title == "One" })
        let two = try XCTUnwrap(parsed.chapters.first { $0.title == "Two" })
        XCTAssertTrue(try LocalBook.content(book: parsed.book, chapter: one).contains("FIRST_START"))
        XCTAssertFalse(try LocalBook.content(book: parsed.book, chapter: one).contains("SECOND_START"))
        XCTAssertTrue(try LocalBook.content(book: parsed.book, chapter: two).contains("SECOND_START"))
    }

    func testRepeatedChapterReadsDecodeOnlyNeededRecordsAndInvalidateOnModification() throws {
        let texts = ["<h1>One</h1><p>First text</p><mbp:pagebreak/>", "<h1>Two</h1><p>Second text</p><mbp:pagebreak/>", "<h1>Three</h1><p>Third text</p>"]
        func make(_ texts: [String]) throws -> Data {
            var header = try PdbReader(data: MobiPdfTests.mobi()).getRecordData(0)
            put(&header, 8, texts.count, 2); put(&header, 4, texts.reduce(0) { $0 + $1.utf8.count })
            let records = texts.map { text -> Data in
                let raw = Data(text.utf8)
                var encoded = Data()
                for offset in stride(from: 0, to: raw.count, by: 8) {
                    let count = min(8, raw.count - offset)
                    encoded.append(UInt8(count)); encoded.append(raw[offset..<(offset + count)])
                }
                return encoded
            }
            return pdb([header] + records)
        }
        let url = try file(make(texts))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: url.path)
        var decoded: [Int] = []
        MobiReadMetrics.observe { source, record in if source == url { decoded.append(record) } }
        defer { MobiReadMetrics.observe(nil) }
        let parsed = try LocalBook.parse(url: url)
        XCTAssertEqual(parsed.chapters.count, 3)
        guard parsed.chapters.count == 3 else { return }
        decoded = []
        XCTAssertTrue(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[1]).contains("Second text"))
        XCTAssertEqual(decoded, [1])
        decoded = []
        XCTAssertTrue(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[2]).contains("Third text"))
        XCTAssertEqual(decoded, [2])
        decoded = []
        _ = try LocalBook.chapterList(book: parsed.book)
        XCTAssertEqual(decoded, [])
        var changed = texts; changed[2] = changed[2].replacingOccurrences(of: "Third", with: "Fresh")
        try make(changed).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: url.path)
        XCTAssertTrue(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[2]).contains("Fresh text"))
        XCTAssertTrue(decoded.contains(0))
        try make(texts).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200.125)], ofItemAtPath: url.path)
        XCTAssertTrue(try LocalBook.content(book: parsed.book, chapter: parsed.chapters[2]).contains("Third text"))
    }
}
