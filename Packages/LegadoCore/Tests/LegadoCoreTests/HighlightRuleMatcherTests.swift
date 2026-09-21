import XCTest
@testable import LegadoCore

final class HighlightRuleMatcherTests: XCTestCase {
    func testStyleMergeKeepsEarlierDecorationsAndClampsMetrics() {
        let first = HighlightStyle(json: #"{"fill":-256,"fillShape":"PILL","bold":true,"underline":{"kind":"WAVY","width":99},"fontSize":1}"#)
        let second = HighlightStyle(json: #"{"textColor":-65536,"italic":true,"letterSpacing":8,"shadow":{"radius":100,"dx":-100}}"#)
        let merged = first.merging(second)
        XCTAssertEqual(merged.fill, -256); XCTAssertEqual(merged.fillShape, "PILL")
        XCTAssertTrue(merged.bold); XCTAssertTrue(merged.italic)
        XCTAssertEqual(merged.underline?.kind, "WAVY"); XCTAssertEqual(merged.underline?.width, 10)
        XCTAssertEqual(merged.fontSize, 5); XCTAssertEqual(merged.letterSpacing, 1)
        XCTAssertEqual(merged.shadow?.radius, 10); XCTAssertEqual(merged.shadow?.dx, -10)
        XCTAssertEqual(HighlightStyle(json: "invalid"), HighlightStyle())
    }

    func testRegexDeadlineStopsWithDeterministicClock() {
        var rule = HighlightRule(); rule.pattern = "a"; rule.isRegex = true; rule.timeoutMillisecond = 1
        var tick = 0.0
        let result = HighlightRuleMatcher.match(text: "aaaa", titleLength: 0, rules: [rule], book: Book(), clock: {
            defer { tick += 1 }; return tick
        })
        XCTAssertFalse(result.completed); XCTAssertTrue(result.matches.isEmpty)
    }

    func testScopesChannelsAndUTF16Ranges() throws {
        var book = Book(); book.name = "Novel"; book.origin = "https://highlight.test"
        var title = HighlightRule(); title.id = 1; title.pattern = "Word"; title.applyToTitle = true; title.applyToBody = false
        var body = title; body.id = 2; body.applyToTitle = false; body.applyToBody = true; body.scope = "Novel"
        var other = body; other.id = 3; other.scope = "Other"
        var disabled = body; disabled.id = 4; disabled.isEnabled = false
        let result = HighlightRuleMatcher.match(text: "Word\n\u{1f600}Word Word", titleLength: 5, rules: [disabled, other, body, title], book: book)
        XCTAssertTrue(result.completed)
        XCTAssertEqual(result.matches.map(\.ruleID), [1, 2, 2])
        XCTAssertEqual(result.matches.map(\.range), [NSRange(location: 0, length: 4), NSRange(location: 7, length: 4), NSRange(location: 12, length: 4)])
        var empty = Book(); empty.name = ""; empty.origin = ""
        XCTAssertTrue(HighlightRuleMatcher.match(text: "Word", titleLength: 0, rules: [other], book: empty).matches.isEmpty)
    }

    func testRegexSegmentsZeroLengthInvalidAndBoundedMatching() {
        var rule = HighlightRule(); rule.id = 1; rule.isRegex = true; rule.pattern = "a.*b"; rule.applyToTitle = true
        let book = Book()
        XCTAssertEqual(HighlightRuleMatcher.match(text: "a-b", titleLength: 2, rules: [rule], book: book).matches.count, 1)
        rule.applyToTitle = false
        XCTAssertTrue(HighlightRuleMatcher.match(text: "a-b", titleLength: 2, rules: [rule], book: book).matches.isEmpty)
        rule.pattern = "(?=a)|a"
        XCTAssertTrue(HighlightRuleMatcher.match(text: "a", titleLength: 0, rules: [rule], book: book).matches.isEmpty)
        rule.pattern = "["
        XCTAssertTrue(HighlightRuleMatcher.match(text: "a", titleLength: 0, rules: [rule], book: book).completed)
        rule.isRegex = false; rule.pattern = "a"
        let limited = HighlightRuleMatcher.match(text: "aaaa", titleLength: 0, rules: [rule], book: book, maximumMatches: 2)
        XCTAssertEqual(limited.matches.count, 2); XCTAssertFalse(limited.completed)
        XCTAssertFalse(HighlightRuleMatcher.match(text: "aaaa", titleLength: 0, rules: [rule], book: book, shouldContinue: { false }).completed)
    }
}
