import SwiftUI

struct NoAnimTransition: ViewModifier {
    func body(content: Content) -> some View { content.transaction { $0.animation = nil } }
}
