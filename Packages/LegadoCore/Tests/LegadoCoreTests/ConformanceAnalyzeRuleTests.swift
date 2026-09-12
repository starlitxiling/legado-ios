import Foundation
import XCTest
@testable import LegadoCore

final class ConformanceAnalyzeRuleTests: XCTestCase {
    // 规格 §2、§4、§7、§8，L23-74、L120-137、L218-261；按 fixture 原入口执行。
    func testRuleFixtures() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixtureRoot = root.appendingPathComponent("Tests/Conformance/fixtures")
        let cases = try ConformanceRunner.load(directories: [
            fixtureRoot.appendingPathComponent("golden"), fixtureRoot.appendingPathComponent("synthetic")
        ]).filter { test in
            test.id.hasPrefix("golden-ReplacePreviewTest-") || test.kind == "replace" ||
            ["replace", "template", "prefix", "regex", "empty"].contains { test.id.hasPrefix("synthetic-\($0)-") }
        }
        XCTAssertEqual(cases.count, 36)
        let report = ConformanceRunner.run(cases)
        print(report.summary)
        for kind in ["replace", "template", "prefix", "regex", "empty"] {
            let values = report.results.filter { $0.id.hasPrefix("synthetic-\(kind)-") }
            print("unit3 \(kind): passed=\(values.filter { $0.status == .passed }.count), skipped=\(values.filter { $0.status == .skipped }.count), failed=\(values.filter { $0.status == .failed }.count)")
        }
        for (fixture, result) in zip(cases, report.results) {
            print("unit3 \(result.id): \(result.status.rawValue) \(result.detail)")
            if fixture.input.variables?["operation"] == .string("ReplacePreview.apply") {
                XCTAssertEqual(result.status, .unsupported, "UI 预览不属于规则引擎入口")
                XCTAssertTrue(result.detail.contains("ReplacePreview.apply"))
                continue
            }
            switch result.status {
            case .passed: XCTAssertEqual(result.actual, result.expected, result.id)
            case .skipped: assertAllowedSkip(fixture, detail: result.detail)
            case .failed, .unsupported: XCTFail("\(result.id): \(result.detail)")
            }
        }
    }

    private func assertAllowedSkip(_ fixture: ConformanceCase, detail: String, file: StaticString = #filePath, line: UInt = #line) {
        let jsCases: Set<String> = ["synthetic-replace-007", "synthetic-replace-008", "synthetic-template-001", "synthetic-template-002", "synthetic-template-004"]
        let domCases: Set<String> = ["synthetic-template-003", "synthetic-template-006", "synthetic-template-007", "synthetic-prefix-001", "synthetic-prefix-002", "synthetic-prefix-003", "synthetic-prefix-004", "synthetic-empty-003", "synthetic-empty-004"]
        if jsCases.contains(fixture.id) {
            XCTAssertTrue(fixture.input.rule.contains("<js>") || fixture.input.rule.contains("{{"), fixture.id, file: file, line: line)
            XCTAssertEqual(detail, "依赖未安装的 Js 选择器或脚本引擎", fixture.id, file: file, line: line)
        } else if domCases.contains(fixture.id) {
            XCTAssertEqual(fixture.input.documentType, "html", fixture.id, file: file, line: line)
            XCTAssertTrue(fixture.input.rule.lowercased().contains("@css:") || fixture.input.rule.contains("tag."), fixture.id, file: file, line: line)
            XCTAssertEqual(detail, "依赖未安装的 Default 选择器或脚本引擎", fixture.id, file: file, line: line)
        } else if fixture.input.variables?["isUrl"] == .bool(true),
                  [.string("AnalyzeRule.getString"), .string("AnalyzeRule.getStringList")].contains(fixture.input.variables?["operation"]) {
            XCTAssertTrue(detail.contains("URL 后处理"), fixture.id, file: file, line: line)
        } else {
            XCTFail("\(fixture.id) 不允许跳过：\(detail)", file: file, line: line)
        }
    }
}
