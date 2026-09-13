import XCTest
import GRDB
@testable import LegadoCore

final class LocalBookTests: XCTestCase {
    func testFilename() {
        XCTAssertEqual(LocalBook.nameAuthor("《测试书》作者：张三.txt").name, "测试书")
        XCTAssertEqual(LocalBook.nameAuthor("测试书 by 张三.epub").author, "张三")
    }

    func testEncodingsAndOffsets() throws {
        let text = "第一章 开始\n中文正文\n第二章 结束\n最后一行"
        let samples: [(Data, String)] = [
            (Data(text.utf8), "UTF-8"),
            (Data([0xff, 0xfe]) + text.data(using: .utf16LittleEndian)!, "UTF-16LE"),
            (Data([0xfe, 0xff]) + text.data(using: .utf16BigEndian)!, "UTF-16BE")
        ]
        for (data, charset) in samples {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let parser = try TextFileParser(url: url, blockSize: 7)
            XCTAssertEqual(parser.charset, charset)
            let chapters = try parser.chapters(bookURL: url.absoluteString)
            XCTAssertEqual(chapters.count, 2)
            guard chapters.count == 2 else { continue }
            XCTAssertEqual(try parser.content(chapter: chapters[0]).trimmingCharacters(in: .whitespacesAndNewlines), "中文正文")
            XCTAssertEqual(try parser.content(chapter: chapters[1]).trimmingCharacters(in: .whitespacesAndNewlines), "最后一行")
        }
    }

    func testBuiltInDoubleHeadingLookaroundAcrossChunks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        for id: Int64 in [-19, -20] {
            var rule = try XCTUnwrap(TxtTocRule.builtIn.first { $0.id == id })
            rule.enable = true
            let lines = id == -19 ? "第一章 真正的标题\n第一章 这个不要\n正文" : "第一章 这个不要\n第一章 真正的标题\n正文"
            try Data(lines.utf8).write(to: url)
            let parser = try TextFileParser(url: url, blockSize: 7)
            let chapters = try parser.chapters(bookURL: url.absoluteString, rules: [rule])
            XCTAssertTrue(chapters.contains { $0.title == "第一章 真正的标题" }, "\(id)")
        }
    }

    func testGBKAndFallback() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data([0xd6, 0xd0, 0xce, 0xc4]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let parser = try TextFileParser(url: url)
        XCTAssertEqual(parser.charset, "GBK")
        let chapters = try parser.chapters(bookURL: url.absoluteString, rules: [])
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(try parser.content(chapter: chapters[0]), "中文")
    }

    func testLongFallbackAndInvalidOffsets() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        let text = String(repeating: "这是一段没有目录的正文。\n", count: 1500)
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let parser = try TextFileParser(url: url, blockSize: 101)
        let chapters = try parser.chapters(bookURL: url.absoluteString, rules: [])
        XCTAssertGreaterThan(chapters.count, 1)
        XCTAssertEqual(try chapters.map { try parser.content(chapter: $0) }.joined(), text)
        var invalid = chapters[0]
        invalid.start = -1
        XCTAssertThrowsError(try parser.content(chapter: invalid))
    }

    func testV1UpgradePreservesBooksAndRuleEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("db.sqlite").path
        do {
            let writer = try DatabaseQueue(path: path)
            try Migrations.migrator().migrate(writer, upTo: "v1")
            try await writer.write { db in
                var book = BookRow()
                book.bookUrl = "file:///retained.txt"; book.name = "保留书籍"
                try book.insert(db)
            }
        }
        let database = try AppDatabase.file(at: path)
        let books = try await BookshelfRepository(database: database).list()
        XCTAssertEqual(books.first?.name, "保留书籍")
        let repository = TxtTocRuleRepository(database: database)
        let initialRules = try await repository.list()
        var rule = try XCTUnwrap(initialRules.first)
        rule.name = "自定义规则"
        try await repository.save(rule)
        let reopened = try AppDatabase.file(at: path)
        let rules = try await TxtTocRuleRepository(database: reopened).list()
        XCTAssertEqual(rules.count, 26)
        XCTAssertEqual(rules.first?.name, "自定义规则")
    }

    func testRulesMigration() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TxtTocRuleRepository(database: database)
        let rules = try await repository.list()
        XCTAssertEqual(rules.count, 26)
        for rule in rules where !rule.rule.isEmpty { XCTAssertNoThrow(try rule.validate(), rule.name) }
        var edited = rules[0]
        edited.enable = false
        try await repository.save(edited)
        let updated = try await repository.list()
        XCTAssertEqual(updated.first?.enable, false)
    }
}
