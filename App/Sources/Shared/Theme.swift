import SwiftUI

enum Theme {
    static let accent = Color(red: 0.18, green: 0.43, blue: 0.36)
    static let bookTitle = Font.headline
    static let detail = Font.caption

    static func color(_ value: Int) -> Color {
        let argb = UInt32(truncatingIfNeeded: value)
        return Color(.sRGB, red: Double((argb >> 16) & 255) / 255,
                     green: Double((argb >> 8) & 255) / 255, blue: Double(argb & 255) / 255,
                     opacity: Double((argb >> 24) & 255) / 255)
    }
}
