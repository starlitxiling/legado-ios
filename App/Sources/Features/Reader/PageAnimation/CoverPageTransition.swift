import SwiftUI

struct CoverPageTransition: ViewModifier {
    let page: Int
    let forward: Bool
    func body(content: Content) -> some View {
        content.id(page).transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading), removal: .opacity))
    }
}
