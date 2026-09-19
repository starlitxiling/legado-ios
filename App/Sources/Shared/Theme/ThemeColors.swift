import SwiftUI

struct ThemeColors {
    let palette: ThemePalette
    var primary: Color { palette.primary.color }
    var accent: Color { palette.accent.color }
    var background: Color { palette.background.color }
    var bottomBackground: Color { palette.bottomBackground.color }
    var textPrimary: Color { palette.textPrimary.color }
    var textSecondary: Color { palette.textSecondary.color }
    var card: Color { palette.card.color }
    var menu: Color { palette.menu.color }
    var divider: Color { palette.divider.color }
    var error: Color { palette.error.color }
    var success: Color { palette.success.color }
    var highlight: Color { palette.highlight.color }
    var discoveryDot: Color { palette.discoveryDot.color }
    var isNight: Bool { palette.isNight }
    var isEInk: Bool { palette.isEInk }
    var allowsAnimation: Bool { palette.allowsAnimation }
}

private struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue = ThemeColors(palette: .defaultLight)
}

extension EnvironmentValues {
    var themeColors: ThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}
