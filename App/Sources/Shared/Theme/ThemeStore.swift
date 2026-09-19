import Foundation
import Observation

@Observable @MainActor
final class ThemeStore {
    let preferences: AppPreferences

    init(preferences: AppPreferences) { self.preferences = preferences }

    var mode: ThemeMode {
        get { ThemeMode(rawValue: preferences.string("themeMode")) ?? .system }
        set { preferences.set("themeMode", .string(newValue.rawValue)) }
    }
    var presets: [AppThemeConfiguration] { preferences.themes }

    func apply(_ theme: AppThemeConfiguration, systemIsNight: Bool) throws {
        try preferences.applyTheme(theme, systemIsNight: systemIsNight)
    }

    func save(name: String, night: Bool) throws { try preferences.saveTheme(name: name, night: night) }

    func palette(systemIsNight: Bool) -> ThemePalette {
        let night = mode.isNight(systemIsNight: systemIsNight)
        let eink = mode == .eInk
        let suffix = night ? "Night" : ""
        func color(_ key: String, ink: UInt32) -> ARGBColor {
            ARGBColor(eink ? ink : UInt32(truncatingIfNeeded: preferences.integer(key + suffix)))
        }
        return ThemePalette(primary: color("colorPrimary", ink: 0xFFFFFFFF), accent: color("colorAccent", ink: 0xFF000000),
            background: color("colorBackground", ink: 0xFFFFFFFF), bottomBackground: color("colorBottomBackground", ink: 0xFFFFFFFF),
            isNight: night, isEInk: eink)
    }
}

#if canImport(SwiftUI) && os(iOS)
import SwiftUI

extension ARGBColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity) }
}
#endif
