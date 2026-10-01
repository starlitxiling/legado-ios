import SwiftUI

/// Translucent material normally; on the e-ink theme an opaque paper surface with a thin black outline,
/// because e-paper cannot show blur or translucency.
struct InkSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.themeColors) private var colors
    let shape: S
    let material: Material

    func body(content: Content) -> some View {
        if colors.isEInk {
            content.background(colors.background, in: shape).overlay(shape.strokeBorder(Color.black, lineWidth: 1))
        } else {
            content.background(material, in: shape)
        }
    }
}

extension View {
    func inkSurface<S: InsettableShape>(_ shape: S, material: Material = .regularMaterial) -> some View {
        modifier(InkSurface(shape: shape, material: material))
    }

    func inkSurface(material: Material = .regularMaterial) -> some View {
        modifier(InkSurface(shape: Rectangle(), material: material))
    }
}
