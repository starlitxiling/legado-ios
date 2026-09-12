import Foundation
import XCTest
@testable import LegadoCore

final class ConformanceUrlOptionsTests: XCTestCase {
    func testURLFixtures() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixtureRoot = root.appendingPathComponent("Tests/Conformance/fixtures")
        let cases = try ConformanceRunner.load(directories: [
            fixtureRoot.appendingPathComponent("golden"), fixtureRoot.appendingPathComponent("synthetic")
        ])
        let report = ConformanceRunner.run(cases)
        print(report.summary)
        let results = report.results.filter { $0.kind == "url-options" }
        XCTAssertEqual(results.count, 25)
        XCTAssertEqual(results.filter { $0.status == .passed }.count, 23)
        XCTAssertEqual(results.filter { $0.status == .skipped }.map(\.id).sorted(), ["synthetic-url-017", "synthetic-url-018"])
        for result in results {
            print("\(result.id): \(result.status) \(result.detail)")
            switch result.status {
            case .passed: XCTAssertEqual(result.actual, result.expected, result.id)
            case .skipped: XCTAssertFalse(result.detail.isEmpty, result.id)
            case .failed, .unsupported: XCTFail("\(result.id): \(result.detail)")
            }
        }
    }

    func testRunnerDoesNotPassUnknownOperationsOrErrors() throws {
        func fixture(kind: String = "url-options", operation: String, rule: String = "u", expectType: String = "string", expected: String = "GET") throws -> ConformanceCase {
            let object: [String: Any] = [
                "id": "test", "source": ["file": "test", "method": "test", "line": 1, "commit": "test"],
                "kind": kind, "input": ["document": "", "documentType": "text", "rule": rule,
                    "variables": ["operation": operation, "projection": "method"]],
                "expect": ["type": expectType, "value": expected], "notes": "", "requiresAndroid": true
            ]
            return try JSONDecoder().decode(ConformanceCase.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let cases = try [
            fixture(kind: "js", operation: "unknown"),
            fixture(operation: "unknown"),
            fixture(operation: "AnalyzeUrl", rule: "<js>'u'</js>"),
            fixture(operation: "AnalyzeUrl", rule: "u,{js:'1'}"),
            fixture(operation: "AnalyzeUrl", expected: "POST"),
            fixture(operation: "parseDnsIpAddresses", expectType: "error", expected: "OtherError")
        ]
        XCTAssertEqual(ConformanceRunner.run(cases).results.map(\.status), [.unsupported, .skipped, .skipped, .skipped, .failed, .failed])
    }
}
