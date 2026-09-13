import UIKit
import WebKit
import LegadoCore

@MainActor
final class HeadlessWebView: HeadlessWebViewProtocol {
    static func defaultUserAgent() async throws -> String {
        guard UIApplication.shared.applicationState == .active, let window = keyWindow else {
            throw HeadlessWebViewError.notForeground
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        window.addSubview(webView)
        defer { webView.stopLoading(); webView.removeFromSuperview() }
        guard let value = try await webView.evaluateJavaScript("navigator.userAgent") as? String, !value.isEmpty else {
            throw HeadlessWebViewError.unavailable
        }
        return value
    }

    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).first(where: \.isKeyWindow)
    }

    func load(_ request: HeadlessWebViewRequest) async throws -> StrResponse {
        let session = HeadlessWebViewSession(request: request)
        return try await session.run()
    }
}

@MainActor
private final class HeadlessWebViewSession: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let request: HeadlessWebViewRequest
    var webView: WKWebView?
    var continuation: CheckedContinuation<StrResponse, Error>?
    var evaluation: Task<Void, Never>?
    var backgroundObserver: NSObjectProtocol?
    var completed = false

    init(request: HeadlessWebViewRequest) { self.request = request }

    func run() async throws -> StrResponse {
        try Task.checkCancellation()
        guard UIApplication.shared.applicationState == .active, let window = HeadlessWebView.keyWindow else {
            throw HeadlessWebViewError.notForeground
        }
        for pattern in [request.sourceRegex, request.overrideUrlRegex].compactMap({ $0 }) {
            _ = try NSRegularExpression(pattern: pattern)
        }
        guard request.delayTime >= 0 else { throw HeadlessWebViewError.invalidRequest }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "legadoResource")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.resourceScript,
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        if let result = request.result {
            let literal = String(decoding: try JSONSerialization.data(withJSONObject: result, options: .fragmentsAllowed), as: UTF8.self)
            configuration.userContentController.addUserScript(WKUserScript(source: "window.result = \(literal);",
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        webView.navigationDelegate = self
        webView.isUserInteractionEnabled = false
        window.addSubview(webView)
        defer { cleanup() }
        try await WebViewCookies.seed(request, into: webView)
        try Task.checkCancellation()
        guard UIApplication.shared.applicationState == .active else { throw HeadlessWebViewError.notForeground }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                    object: nil, queue: .main) { [weak self] _ in
                        Task { @MainActor in self?.finish(.failure(HeadlessWebViewError.notForeground)) }
                    }
                do { try WebViewCookies.load(request, into: webView) }
                catch { finish(.failure(error)) }
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        evaluation?.cancel()
        evaluation = Task { [weak self] in
            guard let self else { return }
            do {
                let delay = request.javaScript == nil && request.delayTime == 0 ? 900 : request.delayTime
                try await Task.sleep(for: .milliseconds(100) + .milliseconds(delay))
                let sniffing = !(request.sourceRegex ?? "").isEmpty || !(request.overrideUrlRegex ?? "").isEmpty
                if sniffing {
                    if let js = request.javaScript, !js.isEmpty { _ = try await webView.evaluateJavaScript(js) }
                    return
                }
                for attempt in 0...31 {
                    try Task.checkCancellation()
                    let js = request.javaScript.flatMap { $0.isEmpty ? nil : $0 } ?? "document.documentElement.outerHTML"
                    if let value = try await webView.evaluateJavaScript(js), !(value is NSNull) {
                        let body: String
                        if let string = value as? String { body = string }
                        else { body = String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), as: UTF8.self) }
                        await succeed(body, url: webView.url)
                        return
                    }
                    try await Task.sleep(for: .milliseconds(min(attempt + 1, 5) * 200))
                }
                finish(.failure(HeadlessWebViewError.timedOut))
            } catch { if !Task.isCancelled { finish(.failure(error)) } }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           WebViewResourceMatcher.matches(url.absoluteString, pattern: request.overrideUrlRegex) {
            decisionHandler(.cancel)
            Task { await succeed(url.absoluteString, url: request.url.flatMap(URL.init(string:))) }
        } else { decisionHandler(.allow) }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let url = message.body as? String, WebViewResourceMatcher.matches(url, pattern: request.sourceRegex) else { return }
        Task { await succeed(url, url: request.url.flatMap(URL.init(string:))) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(HeadlessWebViewError.unavailable)) }

    private func succeed(_ body: String, url: URL?) async {
        guard !completed, let webView else { return }
        do {
            try await WebViewCookies.synchronize(request, from: webView)
            finish(.success(StrResponse(raw: HttpResponse(status: 200, finalURL: url ?? URL(string: "about:blank")!), body: body)))
        } catch { finish(.failure(error)) }
    }

    private func finish(_ result: Result<StrResponse, Error>) {
        guard !completed else { return }
        completed = true
        continuation?.resume(with: result)
        continuation = nil
    }

    private func cleanup() {
        evaluation?.cancel()
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "legadoResource")
        webView?.removeFromSuperview()
        webView = nil
    }

    private static let resourceScript = """
    (() => {
      const report = value => { try {
        window.webkit.messageHandlers.legadoResource.postMessage(new URL(String(value), document.baseURI).href);
      } catch (_) {} };
      const originalFetch = window.fetch;
      window.fetch = function(input) { report(input instanceof Request ? input.url : input); return originalFetch.apply(this, arguments); };
      const originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) { report(url); return originalOpen.apply(this, arguments); };
      new PerformanceObserver(list => list.getEntries().forEach(entry => report(entry.name))).observe({type:'resource', buffered:true});
    })();
    """
}

@MainActor
enum WebViewCookies {
    static func seed(_ request: HeadlessWebViewRequest, into webView: WKWebView) async throws {
        guard let url = request.url.flatMap(URL.init(string:)), let host = url.host else { return }
        let cookieHeader = request.headers.first { $0.key.lowercased() == "cookie" }?.value ?? ""
        for (name, value) in CookieStore.cookieToMap(CookieStore.mergeCookies(request.cookies, cookieHeader)) {
            if let cookie = HTTPCookie(properties: [.name: name, .value: value, .domain: host, .path: "/", .secure: url.scheme == "https" ? "TRUE" : "FALSE"]) {
                await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            }
        }
    }

    static func load(_ request: HeadlessWebViewRequest, into webView: WKWebView) throws {
        if let userAgent = request.headers.first(where: { $0.key.lowercased() == "user-agent" })?.value { webView.customUserAgent = userAgent }
        if let html = request.html, !html.isEmpty {
            webView.loadHTMLString(html, baseURL: request.url.flatMap(URL.init(string:)))
        } else {
            guard let url = request.url.flatMap(URL.init(string:)), ["https", "http"].contains(url.scheme) else { throw HeadlessWebViewError.invalidRequest }
            var outgoing = URLRequest(url: url, cachePolicy: request.cacheFirst ? .returnCacheDataElseLoad : .useProtocolCachePolicy)
            outgoing.allHTTPHeaderFields = request.headers
            webView.load(outgoing)
        }
    }

    static func synchronize(_ request: HeadlessWebViewRequest, from webView: WKWebView) async throws {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let grouped = Dictionary(grouping: cookies, by: { $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
        for (domain, values) in grouped {
            try await request.saveCookies(url: "https://" + domain, cookie: values.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
        }
        if let tag = request.tag, let host = webView.url?.host ?? request.url.flatMap(URL.init(string:))?.host {
            let applicable = cookies.filter { cookie in
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return host == domain || host.hasSuffix("." + domain)
            }
            try await request.saveCookies(url: tag, cookie: applicable.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
        }
    }
}
