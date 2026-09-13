import Foundation

public struct SourceSessionHttpClient: HttpClient, SourceScriptClient, WebViewCookieSession {
    private let source: BookSource
    private let database: AppDatabase
    private let client: any HttpClient
    private let timeout: TimeInterval
    private let secrets: any SourceSecretStore
    public init(source: BookSource, database: AppDatabase, client: any HttpClient, timeout: TimeInterval = 60,
                secrets: any SourceSecretStore = MemorySourceSecretStore()) {
        self.source = source; self.database = database; self.client = client; self.timeout = timeout
        self.secrets = secrets
    }
    public func send(_ request: HttpRequest) async throws -> HttpResponse {
        var request = request
        request.timeout = min(request.timeout, max(0.001, timeout))
        request.callTimeout = min(request.callTimeout, max(0.001, timeout))
        let state = try await SourceStateRepository(database: database).load(source: source.bookSourceUrl ?? "")
        if let text = state["loginHeader"], let headers = try? JSONDecoder().decode([String: String].self, from: Data(text.utf8)),
           CookieStore.hostKey(request.url.absoluteString) == CookieStore.hostKey(source.bookSourceUrl ?? "") {
            for (name, value) in headers where request.headers.httpHeader(name) == nil { request.headers.setHTTPHeader(name, value) }
        }
        let cookies = CookieStore()
        let login = SourceLogin(database: database, client: client, cookies: cookies, secrets: secrets)
        try await login.restoreCookies()
        let response = try await client.send(request, cookieStore: cookies)
        if request.enabledCookieJar {
            var row = CookieRow(); row.url = CookieStore.hostKey(response.finalURL.absoluteString)
            row.cookie = await cookies.getCookie(url: row.url)
            try await CookieRepository(database: database).upsert(row)
        }
        return response
    }
    public func send(_ request: HttpRequest, cookieStore: CookieStore?) async throws -> HttpResponse {
        // 持久化会话是这里唯一的 Cookie 真源，避免旧流水线快照覆盖已更新的登录状态。
        try await send(request)
    }

    public func saveWebViewCookies(url: String, cookie: String) async throws -> String {
        try await CookieRepository(database: database).mergeWebViewCookie(url: url, cookie: cookie)
    }

    func configureSourceBindings(_ engine: JsEngine) {
        let bridge = SourceScriptBridge(source: source, database: database, secrets: secrets)
        engine.sourceBindingInstaller = { [weak engine] in try bridge.install(in: $0, engine: engine) }
    }

    func loginHeaders(url: String, headers: [String: String]) throws -> [String: String] {
        var result = headers
        guard CookieStore.hostKey(url) == CookieStore.hostKey(source.bookSourceUrl ?? ""),
              let text = try SourceStateRepository(database: database).value(source: source.bookSourceUrl ?? "", key: "loginHeader"),
              let login = try? JSONDecoder().decode([String: String].self, from: Data(text.utf8)) else { return result }
        for (key, value) in login { result.setHTTPHeader(key, value) }
        return result
    }

    func checkResponse(_ response: StrResponse) async throws -> StrResponse {
        try await SourceLogin(database: database, client: client, secrets: secrets).check(source: source, response: response)
    }
}
