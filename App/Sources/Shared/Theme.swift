import SwiftUI

enum Theme {
    static let bookTitle = Font.headline
    static let detail = Font.caption

    static func color(_ value: Int) -> Color {
        ARGBColor(UInt32(truncatingIfNeeded: value)).color
    }
}
