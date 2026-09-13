import SwiftUI
import WebKit
import LegadoCore

struct RssReadView: View {
    @State private var model: RssReadModel
    let client: any HttpClient
    init(article: RssArticle, source: RssSource, repository: RssRepository, client: any HttpClient, startHTML: String? = nil) {
        self.client = client
        _model = State(initialValue: RssReadModel(article: article, source: source, repository: repository, client: client, startHTML: startHTML))
    }
    var body: some View {
        VStack(spacing: 0) {
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).padding() }
            if let content = model.content {
                RssWebView(content: content, source: model.source, client: client, error: $model.error)
            } else if model.error == nil { ProgressView() }
        }
        .navigationTitle(model.article.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.isStartPage {
                Button { Task { await model.toggleStar() } } label: { Image(systemName: model.starred ? "star.fill" : "star") }
            }
            if let url = URL(string: model.article.link) { ShareLink(item: url) }
        }
        .task { await model.load() }
    }
}

private struct RssWebView: UIViewRepresentable {
    let content: RssReadContent
    let source: RssSource
    let client: any HttpClient
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator(source: source, client: client, report: { error = $0 }) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = source.enableJs
        let controller = configuration.userContentController
        if source.enableJs {
            if let script = source.preloadJs, !script.isEmpty {
                controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
            if let script = source.injectJs, !script.isEmpty {
                controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            }
        }
        if let style = source.style, let data = try? JSONEncoder().encode(style) {
            let css = String(decoding: data, as: UTF8.self)
            controller.addUserScript(WKUserScript(source: "var s=document.createElement('style');s.textContent=\(css);document.head.appendChild(s);", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.load(content, in: view) }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.task?.cancel()
        view.stopLoading(); view.navigationDelegate = nil
        view.configuration.userContentController.removeAllUserScripts()
        WKContentRuleListStore.default().removeContentRuleList(forIdentifier: coordinator.ruleID) { _ in }
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let source: RssSource
        let client: any HttpClient
        let report: (String) -> Void
        let ruleID = "rss-" + UUID().uuidString
        var loaded: RssReadContent?
        var task: Task<Void, Never>?
        var cookieRequest: HeadlessWebViewRequest?
        init(source: RssSource, client: any HttpClient, report: @escaping (String) -> Void) {
            self.source = source; self.client = client; self.report = report
        }
        func load(_ content: RssReadContent, in view: WKWebView) {
            guard loaded != content else { return }
            loaded = content; task?.cancel()
            task = Task { [weak view] in
                do {
                    let rules = try RssWebPolicy(source: source).contentRulesJSON()
                    if rules != "[]" {
                        let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: ruleID, encodedContentRuleList: rules)
                        try Task.checkCancellation()
                        if let list { view?.configuration.userContentController.add(list) }
                    }
                    try Task.checkCancellation()
                    switch content {
                    case let .url(value):
                        let request = try await RssService(client: client).webRequest(url: value, source: source)
                        cookieRequest = request
                        if let view {
                            try await WebViewCookies.seed(request, into: view)
                            try Task.checkCancellation()
                            try WebViewCookies.load(request, into: view)
                        }
                    case let .html(html, base):
                        let css = source.style ?? ""
                        let document = "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><style>\(css)</style>" + html
                        view?.loadHTMLString(document, baseURL: base.flatMap(URL.init(string:)))
                    }
                } catch is CancellationError {} catch { report(String(describing: error)) }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
            guard ["http", "https"].contains(url.scheme ?? "") else { decisionHandler(.cancel); return }
            let policy = RssWebPolicy(source: source)
            let client = client
            Task {
                do {
                    let blocked = try await Task.detached { try policy.shouldOverride(url.absoluteString, client: client) }.value
                    decisionHandler(blocked ? .cancel : .allow)
                } catch { report(String(describing: error)); decisionHandler(.cancel) }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let request = cookieRequest else { return }
            Task {
                do { try await WebViewCookies.synchronize(request, from: webView) }
                catch { report(String(describing: error)) }
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as? URLError)?.code != .cancelled { report(String(describing: error)) }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            self.webView(webView, didFail: navigation, withError: error)
        }
    }
}
