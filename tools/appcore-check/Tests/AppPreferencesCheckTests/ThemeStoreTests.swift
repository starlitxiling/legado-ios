import XCTest
import LegadoCore
@testable import SettingsBackupCheck

final class ThemeStoreTests: XCTestCase {
    func testARGBParsingAndAlpha() throws {
        let color = try XCTUnwrap(ARGBColor(hex: "#8A123456"))
        XCTAssertEqual(color.value, 0x8A123456)
        XCTAssertEqual(color.opacity, 138.0 / 255)
        XCTAssertEqual(color.signedValue, Int32(bitPattern: 0x8A123456))
        XCTAssertEqual(ARGBColor(hex: "#123456")?.hex, "#FF123456")
        XCTAssertNil(ARGBColor(hex: "#nope"))
        XCTAssertNil(ARGBColor(hex: "#123"))
    }

    @MainActor func testFourPresetsHaveExactPaletteValues() throws {
        try withPreferences { preferences in
            let store = ThemeStore(preferences: preferences)
            let expected: [[UInt32]] = [[0xFF795548, 0xFFE53935, 0xFFF5F5F5, 0xFFEEEEEE],
                [0xFF03A9F4, 0xFFAD1457, 0xFFF5F5F5, 0xFFEEEEEE],
                [0xFF303030, 0xFFE0E0E0, 0xFF424242, 0xFF424242],
                [0xFF000000, 0xFFFFFFFF, 0xFF000000, 0xFF000000]]
            XCTAssertEqual(store.presets.count, 4)
            for (theme, colors) in zip(store.presets, expected) {
                try store.apply(theme, systemIsNight: false)
                let palette = store.palette(systemIsNight: false)
                XCTAssertEqual([palette.primary.value, palette.accent.value, palette.background.value, palette.bottomBackground.value], colors)
                XCTAssertEqual(palette.isNight, theme.isNightTheme)
            }
        }
    }

    @MainActor func testModeAndPreferenceChangesRefreshPalette() throws {
        try withPreferences { preferences in
            let store = ThemeStore(preferences: preferences)
            store.mode = .system
            XCTAssertFalse(store.palette(systemIsNight: false).isNight)
            XCTAssertTrue(store.palette(systemIsNight: true).isNight)
            store.mode = .light
            XCTAssertFalse(store.palette(systemIsNight: true).isNight)
            store.mode = .dark
            XCTAssertTrue(store.palette(systemIsNight: false).isNight)
            preferences.set("colorAccentNight", .int(Int32(bitPattern: 0xFF112233)))
            XCTAssertEqual(store.palette(systemIsNight: false).accent.value, 0xFF112233)
            preferences.set("themeMode", .string("invalid"))
            XCTAssertEqual(store.mode, .system)
        }
    }

    @MainActor func testEInkDoesNotOverwriteSavedColors() throws {
        try withPreferences { preferences in
            let store = ThemeStore(preferences: preferences)
            try store.apply(store.presets[1], systemIsNight: false)
            let before = store.palette(systemIsNight: false)
            store.mode = .eInk
            let palette = store.palette(systemIsNight: true)
            XCTAssertEqual(palette.background.value, 0xFFFFFFFF)
            XCTAssertEqual(palette.accent.value, 0xFF000000)
            XCTAssertEqual(palette.textPrimary.value, 0xFF000000)
            XCTAssertFalse(palette.allowsAnimation)
            XCTAssertEqual(palette.pageAnimation(2), 4)
            XCTAssertEqual(before.pageAnimation(2), 2)
            store.mode = .light
            XCTAssertEqual(store.palette(systemIsNight: false), before)
        }
    }

    @MainActor func testThemeSaveAndRestoreKeepAndroidFields() throws {
        try withPreferences { preferences in
            let store = ThemeStore(preferences: preferences)
            var theme = store.presets[1]
            theme.transparentNavBar = true
            theme.backgroundImgPath = "bg/test.png"
            theme.backgroundImgBlur = 7
            try store.apply(theme, systemIsNight: false)
            try store.save(name: "Custom", night: false)
            let saved = try XCTUnwrap(store.presets.first { $0.themeName == "Custom" })
            XCTAssertTrue(saved.transparentNavBar)
            XCTAssertEqual(saved.backgroundImgPath, "bg/test.png")
            XCTAssertEqual(saved.backgroundImgBlur, 7)
            let data = try JSONEncoder().encode([saved])
            try preferences.restoreThemes(data)
            let reloaded = AppPreferences(defaults: preferences.defaults)
            XCTAssertEqual(reloaded.themes.first { $0.themeName == "Custom" }, saved)
            XCTAssertTrue(reloaded.currentTheme(name: "Current", night: false).transparentNavBar)
            XCTAssertThrowsError(try store.save(name: "  ", night: false))
        }
    }

    @MainActor func testInvalidThemeIsNotPartiallyApplied() throws {
        try withPreferences { preferences in
            let store = ThemeStore(preferences: preferences)
            let before = preferences.snapshot
            var invalid = store.presets[1]
            invalid.bottomBackground = "broken"
            XCTAssertThrowsError(try store.apply(invalid, systemIsNight: false))
            XCTAssertEqual(preferences.snapshot, before)
        }
    }

    @MainActor private func withPreferences(_ operation: (AppPreferences) throws -> Void) throws {
        let suite = "ThemeStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try operation(AppPreferences(defaults: defaults))
    }
}
