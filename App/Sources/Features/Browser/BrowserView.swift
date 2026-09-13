import SwiftUI
import WebKit

struct BrowserView: View {
    let title: String
    let webView: WKWebView
    let model: BrowserModel
    let onComplete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BrowserPage(webView: webView)
                if let error = model.errorMessage { Text(error).foregroundStyle(.red).padding() }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: onComplete).disabled(model.isCompleting)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

struct BrowserPage: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
