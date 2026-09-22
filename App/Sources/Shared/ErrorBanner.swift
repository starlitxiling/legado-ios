import SwiftUI

extension View {
    func errorBanner(_ error: UserFacingError?, dismiss: @escaping () -> Void,
                     action: @escaping (UserFacingError.Action) -> Void = { _ in }) -> some View {
        overlay(alignment: .top) {
            if let error {
                ErrorBanner(error: error, dismiss: dismiss, action: action).padding()
            }
        }
    }
}

struct ErrorBanner: View {
    let error: UserFacingError
    let dismiss: () -> Void
    var action: (UserFacingError.Action) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(error.title).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("关闭提示", action: dismiss).accessibilityIdentifier("error.dismiss")
            }
            Text(error.message).font(.callout).textSelection(.enabled)
            if !error.actions.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack { actions }
                    VStack(alignment: .leading) { actions }
                }
            }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var actions: some View {
        ForEach(error.actions, id: \.self) { item in
            Button(item.title) { action(item) }.accessibilityIdentifier("error." + item.rawValue)
        }
    }
}
