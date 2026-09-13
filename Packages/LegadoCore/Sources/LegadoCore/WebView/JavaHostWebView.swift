import Foundation

extension JsEngine {
    func evaluateWebRule(_ rule: String, content: Any, context: AnalyzeRule) throws -> String {
        guard !Thread.isMainThread else { throw HeadlessWebViewError.mainThread }
        guard let loader = headlessWebView else { throw HeadlessWebViewError.unavailable }
        let json = try JSONSerialization.data(withJSONObject: JsEngine.nativeValue(content) ?? NSNull(), options: [.fragmentsAllowed, .sortedKeys])
        let url = context.scriptBaseUrl ?? baseUrl
        let headers = try (httpClient as? any SourceScriptClient)?.loginHeaders(url: url, headers: networkSource.headers) ?? networkSource.headers
        let request = HeadlessWebViewRequest(url: url, html: ruleText(context.content),
            headers: headers, javaScript: rule, timeout: 10, cacheFirst: true,
            result: String(decoding: json, as: UTF8.self), cookieStore: cookieStore, tag: networkSource.key,
            cookieSession: httpClient as? any WebViewCookieSession)
        return try HostAsyncBridge.wait { [cookieStore] in
            var request = request
            request.cookies = await cookieStore.getCookie(url: request.tag ?? request.url ?? "")
            let response = try await loader.load(request)
            try await request.persistCookies(responseURL: response.url)
            return response.body
        }
    }
}

extension JavaHostNetwork {
    func callWebView(_ method: String, _ arguments: [Any]) throws -> Any? {
        guard !Thread.isMainThread else { throw HeadlessWebViewError.mainThread }
        if method == "getWebViewUA" {
            guard arguments.isEmpty else { throw JsEngineError.exception("getWebViewUA 参数数量无效") }
            guard let provider = engine.webViewUserAgent else { throw HeadlessWebViewError.unavailable }
            return try HostAsyncBridge.wait(provider)
        }
        func text(_ index: Int) -> String? {
            guard arguments.indices.contains(index), !(arguments[index] is NSNull) else { return nil }
            return ruleText(arguments[index])
        }
        let browser = method == "startBrowser" || method == "startBrowserAwait"
        let verification = method == "getVerificationCode"
        let range = verification ? 1...1 : browser ? 2...(method == "startBrowser" ? 3 : 4) : 3...(method == "webView" ? 4 : 6)
        guard range.contains(arguments.count), method == "webView" || browser || verification || arguments.count >= 4 else {
            throw JsEngineError.exception("\(method) 参数数量无效")
        }
        var request = HeadlessWebViewRequest(url: text(browser || verification ? 0 : 1),
            html: text(browser ? (method == "startBrowser" ? 2 : 3) : verification ? 99 : 0),
            headers: engine.networkSource.headers, javaScript: browser || verification ? nil : text(2),
            cookieStore: engine.cookieStore, tag: engine.networkSource.key,
            cookieSession: engine.httpClient as? any WebViewCookieSession)
        if let client = engine.httpClient as? any SourceScriptClient, let url = request.url {
            request.headers = try client.loginHeaders(url: url, headers: request.headers)
        }
        if !browser && !verification {
            request.cacheFirst = arguments.indices.contains(method == "webView" ? 3 : 4) && (arguments[method == "webView" ? 3 : 4] as? Bool == true)
            request.delayTime = arguments.count > 5 ? (arguments[5] as? NSNumber)?.int64Value ?? 0 : 0
            if method == "webViewGetSource" { request.sourceRegex = text(3) }
            if method == "webViewGetOverrideUrl" { request.overrideUrlRegex = text(3) }
        }
        let input = request, store = engine.cookieStore
        let loader = engine.headlessWebView, interaction = engine.webViewInteraction
        let title = text(1) ?? ""
        let refetch = method == "startBrowserAwait" && (arguments.count < 3 || arguments[2] as? Bool != false)
        let executor = refetch ? try AnalyzeUrlExecutor(text(0) ?? "", engine: engine) : nil
        return try HostAsyncBridge.wait { () async throws -> Any? in
            var request = input
            request.cookies = await store.getCookie(url: request.tag ?? request.url ?? "")
            if verification {
                guard let interaction else { throw HeadlessWebViewError.unavailable }
                let code = try await interaction.getVerificationCode(request)
                try await request.persistCookies(responseURL: request.url ?? "")
                return code
            }
            if browser {
                guard let interaction else { throw HeadlessWebViewError.unavailable }
                if method == "startBrowser" { try await interaction.startBrowser(request, title: title); return nil }
                let result = try await interaction.startBrowserAwait(request, title: title)
                try await request.persistCookies(responseURL: result.url)
                if let executor { return Self.webResponse(try await executor.getStrResponse(useWebView: false)) }
                return Self.webResponse(.init(raw: result.raw, body: result.body))
            }
            guard let loader else { throw HeadlessWebViewError.unavailable }
            let response = try await loader.load(request)
            try await request.persistCookies(responseURL: response.url)
            return response.body
        }
    }

    private static func webResponse(_ value: AnalyzeUrlExecutor.Response) -> [String: Any] {
        ["__strResponse": true, "body": value.body, "url": value.url, "code": value.code,
         "headers": value.headers, "callTime": value.callTime, "isSuccessful": value.isSuccessful,
         "raw": ["url": value.url, "code": value.code, "headers": value.headers, "body": Array(value.raw.body)]]
    }
}
