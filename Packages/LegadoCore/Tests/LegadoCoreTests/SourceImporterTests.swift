import Foundation
import XCTest
@testable import LegadoCore

final class SourceImporterTests: XCTestCase {
    private let importer = SourceImporter(now: { 123456 })

    private func fixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Tests/Conformance/fixtures/import/\(name).json"), encoding: .utf8)
    }

    private func source(_ text: String) throws -> BookSource {
        guard case let .sources(items) = importer.parseBookSources(text), let first = items.first else {
            throw NSError(domain: "Expected sources", code: 1)
        }
        return first.source
    }

    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try GsonJSONDecoder(now: { 123456 }).decode(type, from: Data(text.utf8))
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws {
        XCTAssertEqual(try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value)), value)
    }

    func testCompleteSource() throws {
        let value = try source(fixture("complete"))
        XCTAssertEqual(value.bookSourceUrl, "https://example.invalid/source")
        XCTAssertEqual(value.ruleSearch?.bookList, "class.results")
        XCTAssertEqual(value.ruleExplore?.name, "tag.h2@text")
        XCTAssertEqual(value.ruleBookInfo?.tocUrl, "tag.a@href")
        XCTAssertEqual(value.ruleToc?.chapterName, "text")
        XCTAssertEqual(value.ruleContent?.maxBatchSize, 3)
        XCTAssertEqual(value.ruleReview?.reviewUrl, "/review")
        XCTAssertEqual(value.header, "{\"X-Test\":\"synthetic\"}")
        try roundTrip(value)
    }

    func testRulesAsStrings() throws {
        let value = try source(fixture("string-rules"))
        XCTAssertEqual(value.ruleSearch?.name, "text")
        XCTAssertEqual(value.ruleExplore?.name, "text")
        XCTAssertEqual(value.ruleBookInfo?.name, "text")
        XCTAssertEqual(value.ruleToc?.chapterName, "text")
        XCTAssertEqual(value.ruleContent?.content, "text")
        XCTAssertEqual(value.ruleReview?.contentRule, "text")
        try roundTrip(value)
    }

    func testIntNumericOnly() throws {
        for (input, expected) in [("12", 12), ("12.0", 12), ("-12.9", -12), ("1e2", 100),
                                  ("\"12\"", 0), ("true", 0), ("null", 0), ("[]", 0), ("{}", 0),
                                  ("2147483648", -2147483648)] {
            XCTAssertEqual(try decode(BookSource.self, "{\"weight\":\(input)}").weight, expected, input)
        }
        let value = try source(fixture("weak-types"))
        XCTAssertEqual(value.customOrder, 12)
        XCTAssertEqual(value.weight, 0)
        XCTAssertEqual(value.bookSourceType, 0)
        XCTAssertNil(value.ruleContent?.maxBatchSize)
    }

    func testStringsPreserveGsonLexemes() throws {
        for (input, expected) in [("12.0", Optional("12.0")), ("1e+02", "1e+02"), ("-0", "-0"),
                                  ("9007199254740993", "9007199254740993"), ("true", "true"),
                                  ("false", "false"), ("null", nil), ("[1, true]", "[1,true]"),
                                  ("{\"a\": 12.0}", "{\"a\":12.0}")] {
            XCTAssertEqual(try decode(BookSource.self, "{\"bookSourceName\":\(input)}").bookSourceName, expected)
        }
    }

    func testMissingAndNullDefaults() throws {
        for text in ["{}", "{\"respondTime\":null,\"enabled\":null}"] {
            let value = try decode(BookSource.self, text)
            XCTAssertEqual(value, BookSource())
            XCTAssertEqual(value.respondTime, 180000)
            XCTAssertEqual(value.enabledCookieJar, true)
        }
        XCTAssertEqual(try source(fixture("defaults")).bookSourceName, "")
    }

    func testBooleanAndLongSemantics() throws {
        let value = try decode(BookSource.self, #"{"enabled":"TrUe","enabledExplore":"no","respondTime":"42"}"#)
        XCTAssertTrue(value.enabled)
        XCTAssertFalse(value.enabledExplore)
        XCTAssertEqual(value.respondTime, 42)
        XCTAssertThrowsError(try decode(BookSource.self, #"{"enabled":1}"#))
        XCTAssertThrowsError(try decode(BookSource.self, #"{"respondTime":true}"#))
    }

    func testSourceArraysAndURLWrapper() throws {
        XCTAssertEqual(importer.parseBookSources(try fixture("urls")), .urls(["https://example.invalid/a", "https://example.invalid/b"]))
        XCTAssertEqual(importer.parseBookSources("[]"), .sources([]))
        XCTAssertEqual(importer.parseBookSources(#"{"sourceUrls":[]}"#), .urls([]))
        XCTAssertEqual(importer.parseBookSources(#"{"sourceUrls":[12,true]}"#), .urls(["12", "true"]))
        XCTAssertEqual(importer.parseBookSources("[\(try fixture("defaults"))]"), .sources([ImportedBookSource(source: try source(fixture("defaults")))]))
    }

    func testInvalidSourceShapes() throws {
        for text in ["{}", "[null]", #"["https://example.invalid/a"]"#, #"{"sourceUrls":null}"#,
                     #"{"sourceUrls":[null]}"#, #"{"sourceUrls":[" "]}"#, #"{"bookSourceUrl":" "}"#,
                     #"{"sourceUrls":{}}"#, "{broken}", "", "[1]"] {
            guard case .invalid = importer.parseBookSources(text) else { return XCTFail(text) }
        }
        guard case .invalid = importer.parseBookSources(try fixture("invalid")) else { return XCTFail() }
    }

    func testJavaScriptIsUnsupportedWithoutExecution() throws {
        XCTAssertEqual(importer.parseBookSources(try fixture("javascript")), .jsSource(.unsupported))
        XCTAssertEqual(importer.parseBookSources("arbitrary non-JSON text"), .jsSource(.unsupported))
    }

    func testMalformedAndNullRules() throws {
        XCTAssertNil(try decode(BookSource.self, #"{"ruleSearch":[]}"#).ruleSearch)
        XCTAssertNil(try decode(BookSource.self, #"{"ruleSearch":"null"}"#).ruleSearch)
        for value in ["true", "12", #""broken""#, #""[]""#] {
            XCTAssertThrowsError(try decode(BookSource.self, "{\"ruleSearch\":\(value)}"))
        }
        XCTAssertThrowsError(try decode(SearchRule.self, #""{\"name\":\"x\"} trailing""#))
    }

    func testEntityDefaultsAndRoundTrips() throws {
        let book = try decode(Book.self, "{}")
        XCTAssertEqual(book.origin, "loc_book")
        XCTAssertEqual(book.type, 8)
        XCTAssertEqual(book.latestChapterTime, 123456)
        XCTAssertEqual(book.lastCheckTime, 123456)
        XCTAssertEqual(book.durChapterTime, 123456)
        try roundTrip(book)
        let search = try decode(SearchBook.self, "{}")
        XCTAssertEqual(search.type, 8)
        XCTAssertEqual(search.time, 123456)
        XCTAssertEqual(search.chapterWordCount, -1)
        XCTAssertEqual(search.respondTime, -1)
        try roundTrip(search)
        try roundTrip(try decode(BookChapter.self, #"{"index":12.5,"title":true,"start":"4"}"#))
        XCTAssertEqual(try decode(BookGroup.self, "{}"), BookGroup())
        XCTAssertEqual(BookGroup().groupId, 1)
        XCTAssertEqual(BookGroup().bookSort, -1)
        try roundTrip(BookGroup())
        try roundTrip(Cookie())
        let record = try decode(ReadRecord.self, "{}")
        XCTAssertEqual(record.lastRead, 123456)
        XCTAssertEqual(record.lastChapterIndex, -1)
        try roundTrip(record)
        let mark = try decode(Bookmark.self, "{}")
        XCTAssertEqual(mark.time, 123456)
        try roundTrip(mark)
        let rule = try decode(ReplaceRule.self, "{}")
        XCTAssertEqual(rule.id, 123456)
        XCTAssertEqual(rule.order, -2147483648)
        XCTAssertEqual(rule.timeoutMillisecond, 3000)
        try roundTrip(rule)
    }

    func testReplacementImports() throws {
        guard case let .rules(items) = importer.parseReplaceRules(try fixture("replace")) else { return XCTFail() }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, 123456)
        XCTAssertEqual(items[0].previewText, "synthetic")
        try roundTrip(items[0])
        guard case .rules = importer.parseReplaceRules(#"{"pattern":"["}"#) else { return XCTFail() }
        XCTAssertEqual(importer.parseReplaceRules(#"[{"pattern":"["}]"#), .rules([]))
        for text in ["{}", "[null]", "not json", #"{"pattern":""}"#] {
            guard case .invalid = importer.parseReplaceRules(text) else { return XCTFail(text) }
        }
    }

    func testLegacyReplacementImport() throws {
        guard case let .rules(items) = importer.parseReplaceRules(try fixture("legacy-replace")) else { return XCTFail() }
        XCTAssertEqual(items[0].pattern, "synthetic")
        XCTAssertEqual(items[0].name, "legacy")
        XCTAssertEqual(items[0].scope, "synthetic book")
        XCTAssertEqual(items[0].order, 2)
        XCTAssertFalse(items[0].isRegex)
        XCTAssertTrue(items[0].isEnabled)
    }

    func testRuleEmptyStringAndSingleUnwrapping() throws {
        XCTAssertNil(try decode(BookSource.self, #"{"ruleSearch":""}"#).ruleSearch)
        XCTAssertNil(try decode(BookSource.self, #"{"ruleSearch":"  "}"#).ruleSearch)
        let twice = try JSONEncoder().encode("\"{}\"")
        XCTAssertThrowsError(try GsonJSONDecoder().decode(SearchRule.self, from: twice))
    }

    func testNestedLexemesAndDuplicateKeys() throws {
        let value = try source(#"{"bookSourceUrl":"https://example.invalid/source","header":{"a":12.0,"b":true,"a":1e2},"ruleSearch":"{\"name\":1e+02}"}"#)
        XCTAssertEqual(value.header, #"{"a":1e2,"b":true}"#)
        XCTAssertEqual(value.ruleSearch?.name, "1e+02")
    }

    func testNonJSONCandidateBranchMatchesKotlin() {
        XCTAssertEqual(importer.parseBookSources("{unfinished"), .jsSource(.unsupported))
        XCTAssertEqual(importer.parseBookSources("[unfinished"), .jsSource(.unsupported))
    }

    func testAllEntityMissingDefaults() throws {
        XCTAssertEqual(try decode(Book.self, "{}"), Book(now: 123456))
        XCTAssertEqual(try decode(SearchBook.self, "{}"), SearchBook(now: 123456))
        XCTAssertEqual(try decode(BookChapter.self, "{}"), BookChapter())
        XCTAssertEqual(try decode(Cookie.self, "{}"), Cookie())
        XCTAssertEqual(try decode(ReadRecord.self, "{}"), ReadRecord(now: 123456))
        XCTAssertEqual(try decode(Bookmark.self, "{}"), Bookmark(now: 123456))
        XCTAssertEqual(try decode(ReplaceRule.self, "{}"), ReplaceRule(now: 123456))
        XCTAssertEqual(try decode(SearchRule.self, "{}"), SearchRule())
        XCTAssertEqual(try decode(ExploreRule.self, "{}"), ExploreRule())
        XCTAssertEqual(try decode(BookInfoRule.self, "{}"), BookInfoRule())
        XCTAssertEqual(try decode(TocRule.self, "{}"), TocRule())
        XCTAssertEqual(try decode(ContentRule.self, "{}"), ContentRule())
        XCTAssertEqual(try decode(ReviewRule.self, "{}"), ReviewRule())
    }

    func testLegacyNumericMapping() {
        guard case let .rules(items) = importer.parseReplaceRules(#"{"regex":"synthetic","id":12.5,"serialNumber":2.5}"#) else { return XCTFail() }
        XCTAssertEqual(items[0].id, 12)
        XCTAssertEqual(items[0].order, 2)
    }

    func testStandardCodableEntryPoint() throws {
        let value = try JSONDecoder().decode(BookSource.self, from: Data(#"{"weight":12.0,"bookSourceName":true,"ruleSearch":"{\"name\":12}"}"#.utf8))
        XCTAssertEqual(value.weight, 12)
        XCTAssertEqual(value.bookSourceName, "true")
        XCTAssertEqual(value.ruleSearch?.name, "12")
        try roundTrip(value)
    }
}
