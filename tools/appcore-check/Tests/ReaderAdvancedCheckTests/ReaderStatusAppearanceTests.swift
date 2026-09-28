import XCTest
import SwiftUI
@testable import ReaderCheck

final class ReaderStatusAppearanceTests: XCTestCase {
    func testReaderStatusIconsDoNotOverrideApplicationScheme() {
        let dark = ThemePalette(primary: ARGBColor(0xFF000000), accent: ARGBColor(0xFFFFFFFF),
            background: ARGBColor(0xFF000000), bottomBackground: ARGBColor(0xFF000000), isNight: true, isEInk: false)
        let appearance = ReaderStatusAppearance(mode: .dark, palette: dark, darkIcons: true)
        XCTAssertEqual(appearance.colorScheme, .dark)
        XCTAssertEqual(appearance.darkStatusIcons, true)
        let light = ReaderStatusAppearance(mode: .light, palette: .defaultLight, darkIcons: false)
        XCTAssertEqual(light.colorScheme, .light)
        XCTAssertEqual(light.darkStatusIcons, false)
        XCTAssertNil(ReaderStatusAppearance(mode: .system, palette: dark, darkIcons: true).colorScheme)
    }
}
