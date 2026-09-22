import Foundation

enum ThemeMode: String, CaseIterable {
    case system = "0", light = "1", dark = "2", eInk = "3"

    func isNight(systemIsNight: Bool) -> Bool {
        self == .dark || (self == .system && systemIsNight)
    }
}

struct ARGBColor: Equatable {
    let value: UInt32
    init(_ value: UInt32) { self.value = value }
    init?(hex: String) {
        let text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard [6, 8].contains(text.count), let number = UInt32(text, radix: 16) else { return nil }
        value = text.count == 6 ? number | 0xFF000000 : number
    }
    var signedValue: Int32 { Int32(bitPattern: value) }
    var hex: String { String(format: "#%08X", value) }
    var red: Double { Double((value >> 16) & 255) / 255 }
    var green: Double { Double((value >> 8) & 255) / 255 }
    var blue: Double { Double(value & 255) / 255 }
    var opacity: Double { Double((value >> 24) & 255) / 255 }
    var isDark: Bool { red * 0.299 + green * 0.587 + blue * 0.114 < 0.5 }
}

struct ThemePalette: Equatable {
    let primary: ARGBColor
    let accent: ARGBColor
    let background: ARGBColor
    let bottomBackground: ARGBColor
    let isNight: Bool
    let isEInk: Bool
    var allowsAnimation: Bool { !isEInk }
    func pageAnimation(_ savedMode: Int, eInkMode: Int = 4) -> Int { isEInk ? eInkMode : savedMode }
    var onPrimary: ARGBColor { ARGBColor(primary.isDark ? 0xFFFFFFFF : 0xFF000000) }
    var onAccent: ARGBColor { ARGBColor(accent.isDark ? 0xFFFFFFFF : 0xFF000000) }
    var textPrimary: ARGBColor { ARGBColor(isEInk ? 0xFF000000 : isNight ? 0xFFFFFFFF : 0xDE000000) }
    var textSecondary: ARGBColor { ARGBColor(isEInk ? 0xFF000000 : isNight ? 0xB3FFFFFF : 0x8A000000) }
    var card: ARGBColor { ARGBColor(isEInk ? 0xFFFFFFFF : isNight ? 0xFF303030 : 0xFFF5F5F5) }
    var menu: ARGBColor { ARGBColor(isEInk ? 0xFFFFFFFF : isNight ? 0xFF424242 : 0xFFEEEEEE) }
    var divider: ARGBColor { ARGBColor(isEInk ? 0xFF000000 : isNight ? 0xFF363636 : 0x66666666) }
    var error: ARGBColor { ARGBColor(isEInk ? 0xFF000000 : 0xFFEB4333) }
    var success: ARGBColor { ARGBColor(isEInk ? 0xFF000000 : 0xFF439B53) }
    var highlight: ARGBColor { ARGBColor(isEInk ? 0xFF000000 : 0xFFD3321B) }
    var discoveryDot: ARGBColor { ARGBColor(isEInk ? 0xFF000000 : 0xFF43A047) }

    static let defaultLight = ThemePalette(primary: ARGBColor(0xFF795548), accent: ARGBColor(0xFFE53935),
        background: ARGBColor(0xFFF5F5F5), bottomBackground: ARGBColor(0xFFEEEEEE), isNight: false, isEInk: false)
}
