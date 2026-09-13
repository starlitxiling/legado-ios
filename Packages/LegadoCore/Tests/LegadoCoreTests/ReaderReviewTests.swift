import XCTest
@testable import LegadoCore

final class ReaderReviewTests: XCTestCase {
    func testSummaryTrimsAndTruncatesDecimalStrings() throws {
        var rule = ReviewRule(); rule.enabled = true
        rule.summaryListRule = "$.items[*]"; rule.summaryParagraphIndexRule = "$.index"; rule.summaryCountRule = "$.count"
        let result = try ReaderReviewEvaluator.summary(body: #"{"items":[{"index":" 3.9 ","count":" 2.8 "},{"index":" 7 ","count":" 4 "}]}"#, rule: rule)
        XCTAssertEqual(result.counts, [3: 2, 7: 4])
    }
    func testSummaryRulesIgnoreZeroAndUseOneBasedFallback() throws {
        var rule = ReviewRule()
        rule.enabled = true
        rule.summaryListRule = "$.items[*]"
        rule.summaryParagraphIndexRule = "$.index"
        rule.summaryCountRule = "$.count"
        rule.summaryParagraphDataRule = "$.key"
        let result = try ReaderReviewEvaluator.summary(body: #"{"items":[{"index":3,"count":2,"key":"p3"},{"index":0,"count":8},{"count":4}]}"#, rule: rule)
        XCTAssertEqual(result.counts, [3: 4])
    }

    func testDetailRulesOnlyReadConfiguredFields() throws {
        var rule = ReviewRule()
        rule.enabled = true
        rule.detailListRule = "$.items[*]"
        rule.detailNameRule = "$.name"
        rule.detailContentRule = "$.text"
        let result = try ReaderReviewEvaluator.details(body: #"{"items":[{"name":"读者","text":"段评内容"}]}"#, rule: rule)
        XCTAssertEqual(result.first?.name, "读者")
        XCTAssertEqual(result.first?.content, "段评内容")
        rule.enabled = false
        XCTAssertTrue(try ReaderReviewEvaluator.details(body: "invalid", rule: rule).isEmpty)
    }
}
