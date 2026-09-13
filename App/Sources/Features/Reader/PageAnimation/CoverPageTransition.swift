import SwiftUI

struct CoverPageTransition: ViewModifier {
    let page: Int
    func body(content: Content) -> some View {
        content.id(page).transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
    }
}
