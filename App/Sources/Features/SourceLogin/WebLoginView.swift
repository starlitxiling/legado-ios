import SwiftUI
import WebKit
import LegadoCore

struct WebLoginView: View {
    let url: URL
    let service: SourceLogin
    @State private var webView = WKWebView(frame: .zero, configuration: WebLoginView.configuration())
    @State private var errorMessage: String?
    @State private var saving = false
    @State private var model: SourceLoginViewModel
    @Environment(\.dismiss) private var dismiss

    init(url: URL, service: SourceLogin) {
        self.url = url; self.service = service
        var source = BookSource(); source.loginUrl = url.absoluteString
        _model = State(initialValue: SourceLoginViewModel(source: source, service: service))
    }

    var body: some View {
        WebLoginBrowser(webView: webView, url: url)
            .navigationTitle("网页登录")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        saving = true
                        let finalURL = webView.url
                        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                            Task { @MainActor in
                                await model.completeWebLogin(cookies: cookies, currentURL: finalURL)
                                if model.completed { dismiss() }
                                errorMessage = model.errorMessage
                                saving = false
                            }
                        }
                    }.disabled(saving)
                }
            }
            .overlay(alignment: .bottom) {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding().background(.regularMaterial) }
            }
    }
    private static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return configuration
    }
}

private struct WebLoginBrowser: UIViewRepresentable {
    let webView: WKWebView
    let url: URL
    func makeUIView(context: Context) -> WKWebView { webView.load(URLRequest(url: url)); return webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct SourceLoginDestination: View {
    let source: BookSource
    let service: SourceLogin
    var body: some View {
        if let ui = source.loginUi, !ui.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ui.replacingOccurrences(of: " ", with: "") != "[]" {
            FormLoginView(source: source, service: service)
        } else if let address = source.loginUrl, let url = URL(string: address), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            WebLoginView(url: url, service: service)
        } else {
            ContentUnavailableView("没有可用的登录页面", systemImage: "person.crop.circle.badge.exclamationmark")
        }
    }
}
