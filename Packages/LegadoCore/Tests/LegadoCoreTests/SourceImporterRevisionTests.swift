import Foundation
import XCTest
@testable import LegadoCore

final class SourceImporterRevisionTests: XCTestCase {
    private let decoder = GsonJSONDecoder(now: { 123456 })
    private let importer = SourceImporter(now: { 123456 })

    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try decoder.decode(type, from: Data(text.utf8))
    }

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    func testReadConfigPreservesEveryNonDefaultField() throws {
        let json = #"{"readConfig":{"reverseToc":true,"reverseTocDisplay":true,"tocExpanded":false,"pageAnim":2,"reSegment":true,"imageStyle":"FULL","useReplaceRule":false,"delTag":6,"ttsEngine":"synthetic","splitLongChapter":false,"readSimulating":true,"startDate":"2024-02-29","startChapter":7,"dailyChapters":8,"openCredits":9,"closeCredits":10,"playMode":11,"playSpeed":1.5,"useGlobalAudioSkip":true,"manualReplaceRuleIds":[12,13]}}"#
        let book = try decode(Book.self, json)
        let encoded = try object(book)
        let config = try XCTUnwrap(encoded["readConfig"] as? NSDictionary)
        let input = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(config, input["readConfig"] as? NSDictionary)
        XCTAssertEqual(try decoder.decode(Book.self, from: JSONEncoder().encode(book)), book)
    }

    func testMissingNullAndFailedConversionAreDistinct() throws {
        let absent = try decode(BookSource.self, "{}")
        XCTAssertEqual(absent.bookSourceName, "")
        XCTAssertEqual(absent.enabledCookieJar, true)
        let explicit = try decode(BookSource.self, #"{"bookSourceName":null,"enabledCookieJar":null,"weight":null,"enabled":null}"#)
        XCTAssertNil(explicit.bookSourceName)
        XCTAssertNil(explicit.enabledCookieJar)
        XCTAssertEqual(explicit.weight, 0)
        XCTAssertTrue(explicit.enabled)
        let encoded = try object(explicit)
        XCTAssertTrue(encoded["bookSourceName"] is NSNull)
        XCTAssertTrue(encoded["enabledCookieJar"] is NSNull)
        XCTAssertEqual(try decoder.decode(BookSource.self, from: JSONEncoder().encode(explicit)), explicit)
        XCTAssertEqual(try decode(BookSource.self, #"{"weight":"bad"}"#).weight, 0)
        XCTAssertThrowsError(try decode(BookSource.self, #"{"enabledCookieJar":{}}"#))
    }

    func testBoxedIntegerAdapter() throws {
        XCTAssertEqual(try decode(ContentRule.self, #"{"maxBatchSize":"3"}"#).maxBatchSize, 3)
        XCTAssertEqual(try decode(ContentRule.self, #"{"maxBatchSize":3.0}"#).maxBatchSize, 3)
        XCTAssertThrowsError(try decode(ContentRule.self, #"{"maxBatchSize":true}"#))
        XCTAssertThrowsError(try decode(ContentRule.self, #"{"maxBatchSize":"bad"}"#))
        XCTAssertNil(try decode(ContentRule.self, #"{"maxBatchSize":null}"#).maxBatchSize)
    }

    func testLongUsesJsonReaderSemantics() throws {
        XCTAssertThrowsError(try decode(BookSource.self, #"{"respondTime":12.5}"#))
        XCTAssertThrowsError(try decode(BookSource.self, #"{"respondTime":18446744073709551616}"#))
        XCTAssertEqual(try decode(BookSource.self, #"{"respondTime":"1e2"}"#).respondTime, 100)
        XCTAssertEqual(try decode(BookSource.self, #"{"respondTime":12.0}"#).respondTime, 12)
        XCTAssertEqual(try decode(BookSource.self, #"{"respondTime":"9223372036854775807"}"#).respondTime, Int64.max)
        XCTAssertThrowsError(try decode(BookChapter.self, #"{"start":12.5}"#))
    }

    func testTrailingPipeReplacementFilter() throws {
        guard case let .rules(rules) = importer.parseReplaceRules(#"[{"pattern":"a|"},{"pattern":"a\\|"},{"pattern":"a|","isRegex":false}]"#) else { return XCTFail() }
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules.first?.pattern, #"a\|"#)
        XCTAssertEqual(rules.last?.isRegex, false)
    }

    func testJSONJavaScriptSourcesCarryPerItemSupport() throws {
        let text = #"[{"bookSourceUrl":"https://example.invalid/plain"},{"bookSourceUrl":"https://example.invalid/js","mainJs":"function search() {}"}]"#
        guard case let .sources(items) = importer.parseBookSources(text) else { return XCTFail() }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.support), [.supported, .unsupportedJavaScript])
        XCTAssertEqual(items[1].source.mainJs, "function search() {}")
        XCTAssertEqual(items[1].source.bookSourceUrl, "https://example.invalid/js")
        guard case let .sources(single) = importer.parseBookSources(#"{"bookSourceUrl":"https://example.invalid/js","mainJs":"x"}"#) else { return XCTFail() }
        XCTAssertEqual(single.first?.support, .unsupportedJavaScript)
        guard case let .sources(blank) = importer.parseBookSources(#"{"bookSourceUrl":"https://example.invalid/blank","mainJs":"  "}"#) else { return XCTFail() }
        XCTAssertEqual(blank.first?.support, .supported)
    }

    func testReadConfigDefaultsAndDateAdapter() throws {
        XCTAssertEqual(try decode(ReadConfig.self, "{}"), ReadConfig())
        let defaults = try object(ReadConfig())
        XCTAssertEqual(defaults.count, 20)
        XCTAssertEqual(defaults["dailyChapters"] as? Int, 3)
        XCTAssertEqual(defaults["playSpeed"] as? Float, 1)
        XCTAssertEqual(defaults["tocExpanded"] as? Bool, true)
        XCTAssertEqual(defaults["splitLongChapter"] as? Bool, true)
        XCTAssertEqual(defaults["manualReplaceRuleIds"] as? [Int], [])
        let legacy = try decode(ReadConfig.self, #"{"startDate":{"year":"2024","month":2,"day":29}}"#)
        XCTAssertEqual(legacy.startDate, KotlinLocalDate(year: 2024, month: 2, day: 29))
        XCTAssertEqual(try object(legacy)["startDate"] as? String, "2024-02-29")
        for input in [#""2023-02-29""#, #"{"year":2024,"month":2.0,"day":29}"#, "true", "null"] {
            XCTAssertNil(try decode(ReadConfig.self, "{\"startDate\":\(input)}").startDate)
        }
        let nulls = try decode(ReadConfig.self, #"{"manualReplaceRuleIds":null,"useReplaceRule":null}"#)
        XCTAssertNil(nulls.manualReplaceRuleIds)
        XCTAssertTrue(try object(nulls)["manualReplaceRuleIds"] is NSNull)
        XCTAssertEqual(try decode(ReadConfig.self, #"{"manualReplaceRuleIds":[1,null,"2"]}"#).manualReplaceRuleIds, [1, nil, 2])
    }

    func testReferenceNullsAcrossEntities() throws {
        func check<T: Codable & Equatable>(_ instance: T) throws {
            var fields = try object(instance)
            let references = fields.filter { $0.value is String || $0.value is NSNull || $0.value is NSArray || $0.value is NSDictionary }.map(\.key)
            for key in references { fields[key] = NSNull() }
            let value = try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: fields))
            let encoded = try object(value)
            for key in references { XCTAssertTrue(encoded[key] is NSNull, "\(T.self).\(key)") }
            XCTAssertEqual(try decoder.decode(T.self, from: JSONEncoder().encode(value)), value)
        }
        try check(BookSource())
        try check(Book(now: 123456))
        try check(BookChapter())
        try check(SearchBook(now: 123456))
        try check(BookGroup())
        try check(Cookie())
        try check(ReadRecord(now: 123456))
        try check(Bookmark(now: 123456))
        try check(ReplaceRule(now: 123456))
        try check(SearchRule())
        try check(ExploreRule())
        try check(BookInfoRule())
        try check(TocRule())
        try check(ContentRule())
        try check(ReviewRule())
        try check(ReadConfig())
    }

    func testRuleObjectAndStringUseTheirGsonReaders() throws {
        XCTAssertEqual(try decode(BookSource.self, #"{"ruleContent":{"maxBatchSize":3.5}}"#).ruleContent?.maxBatchSize, 3)
        XCTAssertThrowsError(try decode(BookSource.self, #"{"ruleContent":{"maxBatchSize":"3.0"}}"#))
        XCTAssertEqual(try decode(BookSource.self, #"{"ruleContent":"{\"maxBatchSize\":\"3.0\"}"}"#).ruleContent?.maxBatchSize, 3)
        XCTAssertThrowsError(try decode(BookSource.self, #"{"ruleContent":"{\"maxBatchSize\":3.5}"}"#))
        XCTAssertEqual(try decode(ReadConfig.self, #"{"pageAnim":"3.0"}"#).pageAnim, 3)
        XCTAssertThrowsError(try decode(ReadConfig.self, #"{"pageAnim":3.5}"#))
    }
}
