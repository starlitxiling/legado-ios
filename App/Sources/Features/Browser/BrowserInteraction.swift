import SwiftUI
import WebKit
import LegadoCore

@MainActor
final class BrowserInteraction: WebViewUserInteraction {
    @MainActor
    private final class RequestState {
        let id = UUID()
        var cancelled = false
    }
    private var controller: UIViewController?
    private var webView: WKWebView?
    private var activeID: UUID?
    private var completion: ((Result<StrResponse, Error>) -> Void)?
    private var backgroundObserver: NSObjectProtocol?

    func getVerificationCode(_ request: HeadlessWebViewRequest) async throws -> String {
        try await awaitResult(request, title: "验证码", verification: true).body
    }

    func startBrowser(_ request: HeadlessWebViewRequest, title: String) async throws {
        try await present(request, title: title, verification: false, state: RequestState()) { _ in }
    }

    func startBrowserAwait(_ request: HeadlessWebViewRequest, title: String) async throws -> StrResponse {
        try await awaitResult(request, title: title, verification: false)
    }

    private func awaitResult(_ request: HeadlessWebViewRequest, title: String, verification: Bool) async throws -> StrResponse {
        let state = RequestState()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                Task {
                    do {
                        try await present(request, title: title, verification: verification, state: state) { continuation.resume(with: $0) }
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { Task { @MainActor in
            state.cancelled = true
            if self.activeID == state.id { self.finish(.failure(CancellationError())) }
        } }
    }

    private func present(_ request: HeadlessWebViewRequest, title: String, verification: Bool, state: RequestState,
                         completion: @escaping (Result<StrResponse, Error>) -> Void) async throws {
        if state.cancelled { throw CancellationError() }
        let id = state.id
        guard activeID == nil else { throw HeadlessWebViewError.interactionBusy }
        guard UIApplication.shared.applicationState == .active, var presenter = HeadlessWebView.keyWindow?.rootViewController else {
            throw HeadlessWebViewError.notForeground
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        activeID = id
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        do {
            try await WebViewCookies.seed(request, into: webView)
            guard !state.cancelled, activeID == id, UIApplication.shared.applicationState == .active else { throw CancellationError() }
            try WebViewCookies.load(request, into: webView)
        } catch {
            if activeID == id { activeID = nil; self.webView = nil }
            throw error
        }
        self.completion = completion
        let model = BrowserModel()
        let done: (String?) -> Void = { [weak self] code in
            guard let self, !model.isCompleting else { return }
            model.isCompleting = true
            Task {
                do {
                    let body: String
                    if let code { body = code }
                    else { body = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? "" }
                    try await WebViewCookies.synchronize(request, from: webView)
                    guard self.activeID == id else { return }
                    self.finish(.success(StrResponse(raw: HttpResponse(status: 200,
                        finalURL: webView.url ?? request.url.flatMap(URL.init(string:)) ?? URL(string: "about:blank")!), body: body)))
                } catch { model.errorMessage = String(describing: error); model.isCompleting = false }
            }
        }
        let cancel: () -> Void = { [weak self] in self?.finish(.failure(CancellationError())) }
        let view: AnyView = verification
            ? AnyView(VerificationCodeView(webView: webView, model: model, onComplete: { done($0) }, onCancel: cancel))
            : AnyView(BrowserView(title: title, webView: webView, model: model, onComplete: { done(nil) }, onCancel: cancel))
        let controller = UIHostingController(rootView: view)
        controller.isModalInPresentation = true
        self.controller = controller
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.finish(.failure(HeadlessWebViewError.notForeground)) }
            }
        presenter.present(controller, animated: true)
    }

    private func finish(_ result: Result<StrResponse, Error>) {
        let callback = completion
        completion = nil
        activeID = nil
        webView?.stopLoading()
        webView = nil
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        backgroundObserver = nil
        controller?.dismiss(animated: true)
        controller = nil
        callback?(result)
    }
}
