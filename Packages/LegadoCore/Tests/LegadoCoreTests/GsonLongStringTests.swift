import Foundation
import XCTest
@testable import LegadoCore

final class GsonLongStringTests: XCTestCase {
    private struct Fixture: Decodable {
        let field: String
        let unit: String
        let repeatCount: Int
    }

    func testSyntheticLongStringIsNotTruncatedByTokenization() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf:
            root.appendingPathComponent("Tests/Conformance/fixtures/import/long-string.json")))
        let value = String(repeating: fixture.unit, count: fixture.repeatCount)
        let input = try JSONSerialization.data(withJSONObject: [
            fixture.field: value, "bookSourceUrl": "https://example.invalid/source"
        ])
        let decoded = try GsonJSONDecoder().decode(BookSource.self, from: input)
        XCTAssertEqual(decoded.exploreUrl?.count, value.count)
        XCTAssertTrue(decoded.exploreUrl == value)
    }

    func testLargeEscapedUnicodeStringsAndFollowingFields() throws {
        let value = String(repeating: "合成\"\\\n\u{2028}", count: 50000)
        let record: [String: Any] = [
            "bookSourceUrl": "https://example.invalid/source", "exploreUrl": value,
            "weight": 12, "ruleSearch": ["name": value], "unknownSyntheticField": value
        ]
        let input = try JSONSerialization.data(withJSONObject: [record, record])
        let decoder = GsonJSONDecoder()
        let sources = try decoder.decode([BookSource].self, from: input)
        XCTAssertEqual(sources.count, 2)
        for source in sources {
            XCTAssertTrue(source.exploreUrl == value)
            XCTAssertTrue(source.ruleSearch?.name == value)
            XCTAssertEqual(source.weight, 12)
        }
        XCTAssertEqual(try decoder.decode([BookSource].self, from: JSONEncoder().encode(sources)), sources)
    }
}
