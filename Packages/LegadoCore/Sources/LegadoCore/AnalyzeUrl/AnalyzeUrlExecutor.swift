import Foundation

public final class AnalyzeUrlExecutor: @unchecked Sendable {
    public struct Source: Sendable {
        public var key: String?
        public var headers: [String: String]
        public var enabledCookieJar: Bool
        public var concurrentRate: String?
        public init(key: String? = nil, headers: [String: String] = [:], enabledCookieJar: Bool = false, concurrentRate: String? = nil) {
            self.key = key; self.headers = headers; self.enabledCookieJar = enabledCookieJar; self.concurrentRate = concurrentRate
        }
    }

    /// 响应正文可以经过脚本处理，raw 始终保存服务器原始字节。
    public struct Response: Sendable {
        public let raw: HttpResponse
        public let body: String
        public let callTime: Int
        public var url: String { raw.finalURL.absoluteString }
        public var code: Int { raw.status }
        public var headers: [String: String] { raw.headers }
        public var isSuccessful: Bool { (200..<300).contains(code) }
        public init(raw: HttpResponse, body: String, callTime: Int = 0) { self.raw = raw; self.body = body; self.callTime = callTime }
    }

    public let url: String
    public let options: UrlOptions
    private let engine: JsEngine
    private let bindings: [String: Any]
    private let source: Source
    private let headers: [String: String]
    private let callTimeout: Int64?

    public init(_ rule: String, engine: JsEngine, bindings: [String: Any] = [:],
                headers: [String: String]? = nil, callTimeout: Int64? = nil) throws {
        self.engine = engine.networkCopy()
        self.bindings = bindings
        self.source = engine.networkSource
        self.headers = headers ?? engine.networkSource.headers
        self.callTimeout = callTimeout
        var result = rule
        let pattern = try NSRegularExpression(pattern: "<js>([\\s\\S]*?)</js>|@js:([\\s\\S]*)", options: .caseInsensitive)
        let text = rule as NSString
        var start = 0
        for match in pattern.matches(in: rule, range: NSRange(location: 0, length: text.length)) {
            let prefix = text.substring(with: NSRange(location: start, length: match.range.location - start)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { result = prefix.replacingOccurrences(of: "@result", with: result) }
            let code = match.range(at: 2).location == NSNotFound ? match.range(at: 1) : match.range(at: 2)
            result = ruleText(try self.engine.evaluateURLScript(text.substring(with: code), bindings: bindings, result: result))
            start = NSMaxRange(match.range)
        }
        let suffix = text.substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
        if !suffix.isEmpty { result = suffix.replacingOccurrences(of: "@result", with: result) }
        result = try self.engine.interpolateURL(result, bindings: bindings)
        if let page = (bindings["page"] as? NSNumber)?.intValue {
            let pagePattern = try NSRegularExpression(pattern: "<([^<>]+)>")
            let original = result as NSString
            for match in pagePattern.matches(in: result, range: NSRange(location: 0, length: original.length)).reversed() {
                let pages = original.substring(with: match.range(at: 1)).components(separatedBy: ",")
                guard page > 0 else { throw JsEngineError.exception("page 必须大于 0") }
                result = (result as NSString).replacingCharacters(in: match.range, with: pages[min(page - 1, pages.count - 1)].trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        let parsed = UrlOptions.parse(result)
        self.options = parsed.options
        if parsed.status == .lenient { engine.logger("链接参数 JSON 格式不规范，请改为规范格式") }
        let base = UrlOptions.parse(engine.baseUrl).url
        var address = URL(string: parsed.url, relativeTo: URL(string: base))?.absoluteURL.absoluteString ?? parsed.url
        if let target = URL(string: address), let scheme = target.scheme, let host = target.host {
            self.engine.baseUrl = "\(scheme)://\(host)" + (target.port.map { ":\($0)" } ?? "")
        }
        if let js = options.js, let value = try self.engine.evaluateURLScript(js, bindings: bindings, result: address) {
            address = ruleText(value)
        }
        url = address
        if options.serverID != nil { engine.logger("AnalyzeUrl：serverID 保留供 U6 WebDAV 凭据选择，普通 HTTP 不使用") }
    }

    public func getStrResponse(jsStr: String? = nil, sourceRegex: String? = nil, useWebView: Bool = true,
                               skipRateLimit: Bool = false) async throws -> Response {
        try await getStrResponseAwait(jsStr: jsStr, sourceRegex: sourceRegex, useWebView: useWebView, skipRateLimit: skipRateLimit)
    }

    public func getStrResponseAwait(jsStr: String? = nil, sourceRegex: String? = nil, useWebView: Bool = true,
                                    isTest: Bool = false, skipRateLimit: Bool = false) async throws -> Response {
        if options.type != nil {
            let data = try await getByteArray()
            return Response(raw: syntheticRaw(), body: data.map { String(format: "%02x", $0) }.joined())
        }
        if !skipRateLimit { try await engine.rateLimiter.acquire(key: source.key, rate: source.concurrentRate) }
        let start = Date()
        do {
            if useWebView && options.useWebView { throw JsEngineError.unimplemented("AnalyzeUrl webView/webJs") }
            let raw = try await request(raw: false)
            var body = try ResponseDecoder.decode(raw.body, headers: raw.headers)
            let contentType = raw.headers.httpHeader("Content-Type") ?? ""
            if contentType.range(of: #"(?i)(?:text|application)/(?:[^;]+\+)?xml"#, options: .regularExpression) != nil,
               !body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<?xml") {
                body = "<?xml version=\"1.0\"?>" + body
            } else if let js = options.bodyJs {
                body = ruleText(try engine.evaluateURLScript(js, bindings: bindings, result: body))
            }
            return Response(raw: raw, body: body, callTime: Int(Date().timeIntervalSince(start) * 1000))
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            guard isTest else { throw error }
            let code: Int
            switch (error as? URLError)?.code {
            case .timedOut: code = -2
            case .cannotFindHost, .dnsLookupFailed: code = -3
            case .cannotConnectToHost: code = -4
            case .networkConnectionLost: code = -5
            case .secureConnectionFailed, .serverCertificateUntrusted: code = -6
            default: code = -7
            }
            return Response(raw: syntheticRaw(), body: String(describing: error), callTime: code)
        }
    }

    public func getResponse() async throws -> HttpResponse { try await getResponseAwait() }
    public func getResponseAwait() async throws -> HttpResponse {
        try await engine.rateLimiter.acquire(key: source.key, rate: source.concurrentRate)
        return try await request(raw: true)
    }
    public func getByteArray() async throws -> Data {
        if url.hasPrefix("data:"), let comma = url.firstIndex(of: ","), url[..<comma].hasSuffix(";base64"),
           let data = Data(base64Encoded: String(url[url.index(after: comma)...]), options: .ignoreUnknownCharacters) { return data }
        return try await getResponse().body
    }

    private func syntheticRaw() -> HttpResponse {
        HttpResponse(status: 200, finalURL: URL(string: url).flatMap { ["http", "https"].contains($0.scheme) ? $0 : nil } ?? URL(string: "http://localhost/")!)
    }

    private func request(raw: Bool) async throws -> HttpResponse {
        var values: [String: Any] = ["method": raw && options.method == "HEAD" ? "GET" : options.method, "retry": options.retry]
        if let body = options.body { values["body"] = body }
        if let charset = options.charset { values["charset"] = charset }
        if let timeout = options.timeout { values["timeout"] = timeout }
        if let redirects = options.followRedirects { values["followRedirects"] = redirects }
        let requestOptions = try UrlOptions.fromJSON(String(decoding: JSONSerialization.data(withJSONObject: values), as: UTF8.self))
        var requestHeaders = headers
        if let session = engine.httpClient as? any SourceScriptClient {
            requestHeaders = try session.loginHeaders(url: url, headers: requestHeaders)
        }
        for (key, value) in options.headers { requestHeaders.setHTTPHeader(key, value) }
        let domain = source.key.flatMap { URL(string: $0)?.host == nil ? $0 : nil } ?? url
        let cookie = await engine.cookieStore.getCookie(url: domain)
        if !cookie.isEmpty { requestHeaders.setHTTPHeader("Cookie", CookieStore.mergeCookies(cookie, requestHeaders.httpHeader("Cookie") ?? "")) }
        try UrlOptions.validateDnsIpProxyCompatibility(proxy: requestHeaders.httpHeader("proxy"), dnsIp: options.dnsIp)
        let json = String(decoding: try JSONSerialization.data(withJSONObject: requestHeaders), as: UTF8.self)
        let capture = RawRequestClient(base: engine.httpClient, store: engine.cookieStore, callTimeout: callTimeout.map { Double($0) / 1000 })
        _ = try await UrlRequestBuilder.execute(url: url, options: requestOptions, sourceHeaderJSON: json,
                                               enabledCookieJar: source.enabledCookieJar, client: capture)
        return await capture.response!
    }
}

/// U1 的重试入口返回解码文本；此适配器保留原始响应，二进制下载不经过字符集解码。
private actor RawRequestClient: HttpClient {
    let base: any HttpClient
    let store: CookieStore
    let callTimeout: TimeInterval?
    var response: HttpResponse?
    init(base: any HttpClient, store: CookieStore, callTimeout: TimeInterval?) {
        self.base = base; self.store = store; self.callTimeout = callTimeout
    }
    func send(_ request: HttpRequest) async throws -> HttpResponse { try await send(request, cookieStore: nil) }
    func send(_ request: HttpRequest, cookieStore: CookieStore?) async throws -> HttpResponse {
        var outgoing = request
        if let callTimeout {
            guard callTimeout >= 0 && callTimeout <= Double(Int32.max) / 1000 else {
                throw JsEngineError.exception("callTimeout 超出有效毫秒范围")
            }
            outgoing.callTimeout = callTimeout == 0 ? .greatestFiniteMagnitude : callTimeout
        }
        let result = try await base.send(outgoing, cookieStore: store)
        response = result
        return HttpResponse(status: result.status, finalURL: result.finalURL)
    }
}
