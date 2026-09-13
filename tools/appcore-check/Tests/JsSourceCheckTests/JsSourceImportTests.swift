import XCTest
import LegadoCore
@testable import JsSourceCheck

final class JsSourceImportTests: XCTestCase {
    @MainActor
    func testPreviewAndConfirmedScriptImport() async throws {
        let repository = BookSourceRepository(database: try .inMemory())
        let model = SourcesViewModel(repository: repository, httpClient: ReplayHttpClient())
        let script = """
        const config={bookSourceName:'JS 合成',bookSourceUrl:'https://example.invalid'};
        function search(){return [];} function getChapters(){return [];} function getContent(){return '正文';}
        """
        await model.prepareImport(text: script)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.importPreview?.jsSourceCount, 1)
        XCTAssertEqual(model.importPreview?.newCount, 1)
        XCTAssertEqual(model.importPreview?.unsupportedCount, 0)
        let before = try await repository.list()
        XCTAssertTrue(before.isEmpty)
        await model.confirmImport()
        XCTAssertNil(model.errorMessage)
        let after = try await repository.list()
        XCTAssertEqual(after.first?.mainJs, script)
        XCTAssertEqual(model.sources.first?.bookSourceName, "JS 合成")
    }
}
