import XCTest
@testable import LegadoCore

final class TextTocParityTests: XCTestCase {
    func testScoringRejectsFrequentShortFalseHeadingsAndRequiresEnoughChapters() throws {
        let content = (1...5).map { "CH \($0)\n" + String(repeating: "VOLUME false\n", count: 4) + String(repeating: "body ", count: 250) + "\n" }.joined()
        let broad = TxtTocRule(id: 1, name: "Broad", rule: "^(?:CH|VOLUME).*$", serialNumber: 0)
        let narrow = TxtTocRule(id: 2, name: "Narrow", rule: "^CH.*$", serialNumber: 1)
        let processor = TxtTitleProcessor(book: Book())
        XCTAssertEqual(try processor.select(content: content, rules: [broad, narrow])?.id, 2)
        XCTAssertNil(try processor.select(content: "CH 1\nShort body", rules: [narrow]))
    }

    func testReplacementBindingsAndInsertedVolume() throws {
        var book = Book(); book.name = "Sample"; book.author = "Writer"
        let processor = TxtTitleProcessor(book: book)
        let first = try processor.replace("CH 1", script: "java.putVolume(book.name); result + ':' + index + ':' + prevLength", index: 1, previousTitle: nil, previousLength: 0)
        XCTAssertEqual(first.title, "CH 1:1:0")
        XCTAssertEqual(first.volumes, ["Sample"])
        let second = try processor.replace("CH 2", script: "lastVolumeTitle + ':' + prevTitle", index: 3, previousTitle: first.title, previousLength: 20)
        XCTAssertEqual(second.title, "Sample:CH 1:1:0")
        XCTAssertThrowsError(try processor.replace("CH", script: "throw new Error('invalid title')", index: 1, previousTitle: nil, previousLength: 0))
    }

    func testLongChapterVolumeChildrenAndStableAndroidURLs() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let body = String(repeating: "A paragraph for the long chapter.\n", count: 4000)
        try Data(("CH 1\n" + body + "CH 2\nEnd").utf8).write(to: url)
        let rule = TxtTocRule(id: 1, name: "Manual", rule: "^CH.*$")
        var book = Book(); book.originName = "long.txt"
        let parser = try TextFileParser(url: url)
        let chapters = try parser.chapters(bookURL: url.absoluteString, rules: [], book: book, selectedRule: rule)
        XCTAssertTrue(chapters[0].isVolume)
        XCTAssertEqual(chapters[0].start, chapters[0].end)
        XCTAssertTrue(chapters[1].title?.hasPrefix("CH 1(") == true)
        XCTAssertEqual(chapters.last?.title, "CH 2")
        XCTAssertEqual(try chapters.dropFirst().dropLast().map { try parser.content(chapter: $0) }.joined(), "\n" + body)
        XCTAssertEqual(try parser.content(chapter: XCTUnwrap(chapters.last)), "\nEnd")
        XCTAssertEqual(chapters[0].url, "1f4ffd553bbfafc9")
        XCTAssertEqual(Set(chapters.compactMap(\.url)).count, chapters.count)
        let unsplit = try parser.chapters(bookURL: url.absoluteString, rules: [], book: book, selectedRule: rule, splitLongChapters: false)
        XCTAssertEqual(unsplit.count, 2)
    }
    func testSelectedRuleCharsetAndModificationPersist() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = "CH 1\n" + String(repeating: "body ", count: 250) + "\nCH 2\nEnd"
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: url.path)
        let rule = TxtTocRule(id: 1, name: "Selected", rule: "^CH.*$", replacement: "result + ':' + index")
        let parsed = try LocalBook.parse(url: url, rules: [rule])
        XCTAssertEqual(parsed.chapters.map(\.title), ["CH 1:1", "CH 2:2"])
        var book = parsed.book
        XCTAssertEqual(book.tocUrl, rule.rule + TxtTitleProcessor.ruleSeparator + rule.replacement)
        XCTAssertEqual(book.charset, "UTF-8")
        XCTAssertFalse(try LocalBook.isModified(book))
        XCTAssertEqual(try LocalBook.chapterList(book: &book, rules: []).map(\.url), parsed.chapters.map(\.url))
        let db = try AppDatabase.inMemory()
        let saved = try await LocalBook.save(book: book, chapters: parsed.chapters, database: db)
        XCTAssertEqual(saved.tocUrl, book.tocUrl)
        XCTAssertEqual(saved.latestChapterTime, 1_000_000)
        try (Data([0xff, 0xfe]) + text.data(using: .utf16LittleEndian)!).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2000)], ofItemAtPath: url.path)
        XCTAssertTrue(try LocalBook.isModified(book))
        let updated = try LocalBook.chapterList(book: &book, rules: [rule])
        XCTAssertEqual(book.charset, "UTF-16LE")
        XCTAssertEqual(updated.map(\.title), parsed.chapters.map(\.title))
        XCTAssertFalse(try LocalBook.isModified(book))
        let refreshed = try await LocalBook.save(book: book, chapters: updated, database: db)
        XCTAssertEqual(refreshed.charset, "UTF-16LE")
        XCTAssertEqual(refreshed.latestChapterTime, 2_000_000)
    }

    func testFrontMatterUsesReplacementAndInsertedVolumesHaveNoBody() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Introduction\nCH 1\nBody\nCH 2\nEnd".utf8).write(to: url)
        let rule = TxtTocRule(id: 1, name: "Script", rule: "^CH.*$", replacement: "if (result === 'CH 1') java.putVolume('Volume'); result + ':' + index")
        let parser = try TextFileParser(url: url)
        let chapters = try parser.chapters(bookURL: url.absoluteString, selectedRule: rule)
        XCTAssertEqual(chapters.map(\.title), ["前言:1", "Volume", "CH 1:2", "CH 2:4"])
        XCTAssertEqual(try parser.content(chapter: chapters[0]), "Introduction\n")
        XCTAssertTrue(chapters[1].isVolume)
        XCTAssertEqual(try parser.content(chapter: chapters[1]), "")
        XCTAssertEqual(try parser.content(chapter: chapters[2]), "\nBody\n")
    }

}
