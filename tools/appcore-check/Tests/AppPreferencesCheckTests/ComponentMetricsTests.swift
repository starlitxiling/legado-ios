import XCTest
@testable import SettingsBackupCheck

final class ComponentMetricsTests: XCTestCase {
    func testFlowWrapsWithoutDroppingOversizedLabels() {
        let frames = ComponentMetrics.flowFrames(sizes: [CGSize(width: 40, height: 20), CGSize(width: 50, height: 30),
            CGSize(width: 120, height: 15), CGSize(width: 10, height: 10)], width: 100)
        XCTAssertEqual(frames, [CGRect(x: 0, y: 0, width: 40, height: 20), CGRect(x: 46, y: 0, width: 50, height: 30),
            CGRect(x: 0, y: 36, width: 120, height: 15), CGRect(x: 0, y: 57, width: 10, height: 10)])
        XCTAssertEqual(ComponentMetrics.flowFrames(sizes: [], width: 0), [])
        XCTAssertEqual(ComponentMetrics.flowFrames(sizes: [CGSize(width: 10, height: 10)], width: 0).first?.origin, .zero)
    }

    func testBadgeAndProgressBoundaries() {
        XCTAssertNil(ComponentMetrics.badgeText(-1))
        XCTAssertNil(ComponentMetrics.badgeText(0))
        XCTAssertEqual(ComponentMetrics.badgeText(99), "99")
        XCTAssertEqual(ComponentMetrics.badgeText(100), "99+")
        XCTAssertEqual(ComponentMetrics.progress(.nan), 0)
        XCTAssertEqual(ComponentMetrics.progress(-1), 0)
        XCTAssertEqual(ComponentMetrics.progress(2), 1)
    }

    func testIconMappingsAreCompleteAndUnknownIconsAreExplicit() {
        XCTAssertEqual(LegadoIcon.symbols.count, 39)
        XCTAssertEqual(LegadoIcon.symbol(for: "ic_bottom_books"), "books.vertical")
        XCTAssertEqual(LegadoIcon.symbol(for: "ic_toc"), "list.bullet")
        XCTAssertEqual(LegadoIcon.symbol(for: "ic_cfg_about"), "info.circle")
        XCTAssertNil(LegadoIcon.symbol(for: "missing"))
        XCTAssertTrue(LegadoIcon.symbols.values.allSatisfy { !$0.isEmpty })
    }
}
