import XCTest
import LegadoCore
@testable import ReaderCheck

final class ReaderStyleSharingTests: XCTestCase {
    @MainActor
    func testNetworkStylesImportJSONAndZIPAndKeepSelectionOnFailure() async throws {
        let suite = "ReaderSharing." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ReaderStyleStore(database: try AppDatabase.inMemory(), defaults: defaults)
        try await store.load()
        let client = ReplayHttpClient(), url = URL(string: "https://example.test/style")!
        var style = ReadBookConfig(); style.name = "Network style"
        for data in [try ReadBookConfig.exportThemes([style]), try ReaderStyleArchive.encode(style, background: { _ in nil })] {
            await client.enqueue(url: url, response: HttpResponse(status: 200, body: data, finalURL: url))
            try await store.importStyles(from: url.absoluteString, client: client)
            XCTAssertEqual(store.current.name, "Network style")
        }
        let count = store.styles.count, selected = store.selected
        await client.enqueue(url: url, response: HttpResponse(status: 404, finalURL: url))
        do { try await store.importStyles(from: url.absoluteString, client: client); XCTFail("Expected HTTP failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("404")) }
        do { try await store.importStyles(from: "file:///style.json", client: client); XCTFail("Expected URL rejection") }
        catch { XCTAssertEqual((error as? URLError)?.code, .badURL) }
        XCTAssertEqual(store.styles.count, count); XCTAssertEqual(store.selected, selected)
    }

    func testSVGCountAspectAndTemplateReplacement() throws {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 24"><text x="4" y="20">{{count}}</text></svg>"#
        XCTAssertEqual(try ReaderReviewIconStyle.aspectRatio(svg), 2)
        XCTAssertTrue(try ReaderReviewIconStyle.document(svg, count: 1200).contains(">999<"))
        XCTAssertThrowsError(try ReaderReviewIconStyle.aspectRatio("<html/>"))
        XCTAssertThrowsError(try ReaderReviewIconStyle.aspectRatio(#"<svg viewBox="0 0 500 20"/>"#))
        XCTAssertThrowsError(try ReaderReviewIconStyle.aspectRatio("<svg><script>alert(1)</script></svg>"))
        var config = ReadBookConfig()
        try ReaderReviewIconStyle.saveTemplate(name: "One", svg: svg, configuration: &config)
        try ReaderReviewIconStyle.saveTemplate(name: "Renamed", svg: svg, configuration: &config)
        XCTAssertEqual(config.reviewIconSvgTemplates.count, 1)
        XCTAssertEqual(config.reviewIconSvgTemplates.first?.name, "Renamed")
        XCTAssertEqual(config.reviewIconSvg, svg)
    }
}
