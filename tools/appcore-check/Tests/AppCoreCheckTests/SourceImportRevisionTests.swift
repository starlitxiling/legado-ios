import Foundation
import XCTest
import LegadoCore
@testable import AppCoreCheck

final class SourceImportRevisionTests: XCTestCase {
    @MainActor
    func testSourceReplacementAppliesBeforePreviewAndRejectsBrokenJSON() async throws {
        let database = try AppDatabase.inMemory()
        let repository = BookSourceRepository(database: database)
        let rules = ReplaceRuleRepository(database: database)
        var rule = ReplaceRuleRow(); rule.id = 1; rule.scopeSource = true; rule.scopeContent = false
        rule.isRegex = false; rule.pattern = "Old"; rule.replacement = "New"
        try await rules.insert(rule)
        let model = SourcesViewModel(repository: repository, httpClient: ReplayHttpClient())
        XCTAssertFalse(model.useSourceReplacement)
        model.useSourceReplacement = true
        await model.prepareImport(text: #"{"bookSourceUrl":"https://source.test","bookSourceName":"Old"}"#)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.importPreview?.newCount, 1)
        await model.confirmImport()
        let stored = try await repository.get(bookSourceUrl: "https://source.test")
        XCTAssertEqual(stored?.bookSourceName, "New")
        rule.pattern = "{"; rule.replacement = "broken"
        try await rules.update(rule)
        await model.prepareImport(text: #"{"bookSourceUrl":"https://other.test"}"#)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.importPreview)
        await model.confirmImport()
        let rejected = try await repository.get(bookSourceUrl: "https://other.test")
        XCTAssertNil(rejected)
    }

    @MainActor
    func testKeepEnableCanBeChangedAfterPreviewWithoutKeepingTimestamp() async throws {
        let repository = BookSourceRepository(database: try .inMemory())
        var source = BookSourceRow()
        source.bookSourceUrl = "https://book.test"
        source.customOrder = -17
        source.enabled = false
        source.enabledExplore = true
        source.lastUpdateTime = 999
        try await repository.upsert(source)
        let model = SourcesViewModel(repository: repository, httpClient: ReplayHttpClient())
        XCTAssertFalse(model.keepEnable)
        await model.prepareImport(text: """
        [{"bookSourceUrl":"https://book.test","customOrder":2,"enabled":true,"enabledExplore":false,"lastUpdateTime":123},
         {"bookSourceUrl":"https://new.test","customOrder":42,"enabled":true,"enabledExplore":false,"lastUpdateTime":456}]
        """)
        model.keepEnable = true
        await model.confirmImport()
        let saved = try await repository.get(bookSourceUrl: source.bookSourceUrl)
        XCTAssertEqual(saved?.customOrder, -17)
        XCTAssertEqual(saved?.enabled, false)
        XCTAssertEqual(saved?.enabledExplore, true)
        XCTAssertEqual(saved?.lastUpdateTime, 123)
        let added = try await repository.get(bookSourceUrl: "https://new.test")
        XCTAssertEqual(added?.customOrder, 42)
        XCTAssertEqual(added?.enabledExplore, false)
    }

    @MainActor
    func testOverwritePreservesLocalOrderAndImportedTimestamp() async throws {
        let repository = BookSourceRepository(database: try .inMemory())
        var source = BookSourceRow()
        source.bookSourceUrl = "https://book.test"
        source.customOrder = 73
        source.enabled = false
        source.enabledExplore = false
        source.lastUpdateTime = 999
        try await repository.upsert(source)
        let model = SourcesViewModel(repository: repository, httpClient: ReplayHttpClient())
        await model.prepareImport(text: """
        {"bookSourceUrl":"https://book.test","customOrder":2,"enabled":true,"enabledExplore":true,"lastUpdateTime":123}
        """)
        await model.confirmImport()
        let saved = try await repository.get(bookSourceUrl: source.bookSourceUrl)
        XCTAssertEqual(saved?.customOrder, 73)
        XCTAssertEqual(saved?.lastUpdateTime, 123)
        XCTAssertEqual(saved?.enabled, true)
        XCTAssertEqual(saved?.enabledExplore, true)
    }

    @MainActor
    func testNonJSONErrorsIncludeOnlyFirst80Characters() async throws {
        let model = SourcesViewModel(repository: .init(database: try .inMemory()), httpClient: ReplayHttpClient())
        for text in ["<html><body>502 Bad Gateway</body></html>", "{\"bookSourceUrl\":\"https://book.test\"", "普通文本" + String(repeating: "甲", count: 100)] {
            await model.prepareImport(text: text)
            XCTAssertNil(model.importPreview)
            let error = try XCTUnwrap(model.errorMessage)
            XCTAssertTrue(error.contains("JSON 无效"), error)
            XCTAssertTrue(error.contains(String(text.prefix(80))), error)
            XCTAssertFalse(error.contains("脚本书源"), error)
            if text.count > 80 { XCTAssertFalse(error.contains(String(text.prefix(81))), error) }
        }
    }

    @MainActor
    func testInvalidJavaScriptReportsInvalidSource() async throws {
        let model = SourcesViewModel(repository: .init(database: try .inMemory()), httpClient: ReplayHttpClient())
        for script in ["function mainJs() { return []; }", "const mainJs = () => [];",
                       "// source\nvar source = {};\nfunction search() { return source; }",
                       "var config = {\nbookSourceUrl: 'https://book.test'\n};\nfunction search() {}"] {
            await model.prepareImport(text: script)
            XCTAssertTrue(model.errorMessage?.contains("JSON 无效") == true)
        }
        for text in ["mainJs download failed", "<html>function mainJs() {}</html>", "{\"mainJs\":\"function mainJs() {}\""] {
            await model.prepareImport(text: text)
            XCTAssertTrue(model.errorMessage?.contains("JSON 无效") == true, model.errorMessage ?? "无错误")
        }
    }
}
