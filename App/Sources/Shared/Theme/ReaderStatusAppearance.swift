import SwiftUI

struct ReaderStatusAppearance {
    let colorScheme: ColorScheme?
    let darkStatusIcons: Bool?

    init(mode: ThemeMode, palette: ThemePalette, darkIcons: Bool?) {
        colorScheme = mode == .system ? nil : palette.isNight ? .dark : .light
        darkStatusIcons = darkIcons
    }
}
