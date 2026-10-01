import SwiftUI

extension View {
    /// Sheets whose content scrolls cannot rely on swipe-to-dismiss alone; every presented page offers 关闭.
    func sheetCloseButton(_ close: @escaping () -> Void) -> some View {
        toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭", action: close).accessibilityIdentifier("sheet.close") } }
    }

    func sheetCloseButton(dismiss: DismissAction) -> some View {
        sheetCloseButton { dismiss() }
    }
}
