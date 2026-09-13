import Foundation
import JavaScriptCore

public enum SourceLoginError: Error, LocalizedError {
    case invalidUI(String)
    case missingLoginScript
    case rejected
    public var errorDescription: String? {
        switch self {
        case .invalidUI(let reason): return "登录表单无效：\(reason)"
        case .missingLoginScript: return "书源缺少 login() 登录脚本"
        case .rejected: return "登录检查未通过"
        }
    }
}

public struct LoginRow: Decodable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let action: String?
    public let defaultValue: String?
    public let viewName: String?
    public let options: [String]?
    public let hint: String?
    enum CodingKeys: String, CodingKey { case name, type, action, defaultValue = "default", viewName, options, hint }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "text"
        action = try c.decodeIfPresent(String.self, forKey: .action)
        defaultValue = try c.decodeIfPresent(String.self, forKey: .defaultValue)
        viewName = try c.decodeIfPresent(String.self, forKey: .viewName)
        options = try c.decodeIfPresent([String].self, forKey: .options)
        hint = try c.decodeIfPresent(String.self, forKey: .hint)
    }
}

public struct LoginActionResult {
    public var updates: [String: String?] = [:]
    public var renderRequested = false
    public var deltaRender = false
}

public actor SourceLogin {
    private let database: AppDatabase
    private let client: any HttpClient
    private let secrets: any SourceSecretStore
    public let cookies: CookieStore
    public init(database: AppDatabase, client: any HttpClient, cookies: CookieStore = CookieStore(),
                secrets: any SourceSecretStore = MemorySourceSecretStore()) {
        self.database = database; self.client = client; self.cookies = cookies; self.secrets = secrets
    }

    public static func parseUI(_ text: String?) throws -> [LoginRow] {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let rows: [LoginRow]
        do { rows = try JSONDecoder().decode([LoginRow].self, from: Data(text.utf8)) }
        catch { throw SourceLoginError.invalidUI("需要 RowUi 数组；暂不支持 v2 表单") }
        guard rows.allSatisfy({ !$0.name.isEmpty && ["text", "password", "button", "label", "select", "toggle"].contains($0.type) }),
              Set(rows.map(\.name)).count == rows.count else { throw SourceLoginError.invalidUI("字段名重复、为空或类型不支持") }
        return rows
    }

    public func rows(source: BookSource) async throws -> [LoginRow] {
        guard let ui = source.loginUi else { return [] }
        if Self.isScript(ui) {
            let value = try await evaluate(source: source, script: Self.script(source.loginUrl ?? "") + "\n" + Self.script(ui))
            if let text = value as? String { return try Self.parseUI(text) }
            guard let value, JSONSerialization.isValidJSONObject(value) else { throw SourceLoginError.invalidUI("脚本未返回数组") }
            return try Self.parseUI(String(decoding: JSONSerialization.data(withJSONObject: value), as: UTF8.self))
        }
        return try Self.parseUI(ui)
    }

    public func storedValues(source: BookSource) async throws -> [String: String] {
        guard let info = try SourceScriptBridge(source: source, database: database, secrets: secrets).read("loginInfo") else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: Data(info.utf8))) ?? [:]
    }

    @discardableResult
    public func submit(source: BookSource, values: [String: String], action: String? = nil) async throws -> LoginActionResult {
        let code = Self.script(source.loginUrl ?? "")
        guard !code.isEmpty, !code.hasPrefix("http://"), !code.hasPrefix("https://") else { throw SourceLoginError.missingLoginScript }
        let bridge = SourceScriptBridge(source: source, database: database, secrets: secrets)
        if action == nil { try bridge.write("loginInfo", value: String(decoding: JSONEncoder().encode(values), as: UTF8.self)) }
        var effects = LoginActionResult()
        _ = try await evaluate(source: source, script: code + "\n" + (action ?? "if(typeof login !== 'function') throw 'Function login not implements'; login.apply(this);"), bindings: ["result": values], mapBindings: ["result"], initializer: { context in
            let update: @convention(block) (JSValue) -> Void = { value in
                guard let dictionary = value.toDictionary() as? [String: Any] else { return }
                for (key, item) in dictionary { effects.updates.updateValue(item is NSNull ? nil : String(describing: item), forKey: key) }
            }
            let render: @convention(block) (Bool) -> Void = { delta in effects.renderRequested = true; effects.deltaRender = delta }
            context.setObject(update, forKeyedSubscript: "__upLoginData" as NSString)
            context.setObject(render, forKeyedSubscript: "__reLoginView" as NSString)
            context.evaluateScript("java.upLoginData=function(v){__upLoginData(v);};java.reLoginView=function(delta){__reLoginView(!!delta);};java.refreshExplore=function(){__reLoginView(false);};")
        })
        return effects
    }

    public func check(source: BookSource, response: HttpResponse) async throws -> HttpResponse {
        try await check(source: source, response: StrResponse(raw: response)).raw
    }

    public func check(source: BookSource, response: StrResponse) async throws -> StrResponse {
        guard let code = source.loginCheckJs, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return response }
        let data: [String: Any] = ["body": response.body, "code": response.code, "url": response.url]
        let loginCode = Self.script(source.loginUrl ?? "")
        let definitions = loginCode.hasPrefix("http://") || loginCode.hasPrefix("https://") ? "" : loginCode
        let setup = definitions + "\nvar result = {body:function(){return __response.body},code:function(){return __response.code},url:function(){return __response.url}};\n"
        let value = try await evaluate(source: source, script: setup + "var __checked = eval(__checkCode); if (__checked === false || __checked == null) throw 'Login check rejected'; ({body:typeof __checked.body === 'function' ? String(__checked.body()) : __response.body, code:typeof __checked.code === 'function' ? Number(__checked.code()) : __response.code, url:typeof __checked.url === 'function' ? String(__checked.url()) : __response.url});", bindings: ["__response": data, "__checkCode": Self.script(code)])
        guard let checked = value as? [String: Any], let body = checked["body"] as? String,
              let status = checked["code"] as? NSNumber, let address = checked["url"] as? String,
              let url = URL(string: address) else { throw SourceLoginError.rejected }
        let raw = HttpResponse(status: status.intValue, body: response.raw.body, finalURL: url, headers: response.headers)
        return StrResponse(raw: raw, body: body)
    }

    public func saveWebCookies(_ values: [HTTPCookie], url: URL) async throws {
        guard let host = url.host?.lowercased() else { throw SourceLoginError.rejected }
        let matching = values.filter {
            let domain = $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return (host == domain || host.hasSuffix("." + domain)) && ($0.expiresDate.map { $0 > Date() } ?? true)
        }
        let cookie = matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        var row = CookieRow(); row.url = CookieStore.hostKey(url.absoluteString); row.cookie = cookie
        try await CookieRepository(database: database).upsert(row)
        await cookies.setCookie(url: row.url, cookie: cookie)
    }

    public func cookieDomains() async throws -> [CookieRow] { try await CookieRepository(database: database).list() }

    public func clearCookies(domain: String) async throws {
        try await SourceStateRepository(database: database).clearCookies(domain: CookieStore.hostKey(domain))
        await cookies.removeCookie(url: domain)
    }

    public func restoreCookies() async throws {
        for row in try await cookieDomains() { await cookies.setCookie(url: row.url, cookie: row.cookie) }
    }

    private func evaluate(source: BookSource, script: String, bindings: [String: Any] = [:], mapBindings: Set<String> = [],
                          initializer: ((JSContext) -> Void)? = nil) async throws -> Any? {
        try Task.checkCancellation()
        let key = source.bookSourceUrl ?? ""
        try await restoreCookies()
        let bridge = SourceScriptBridge(source: source, database: database, secrets: secrets)
        let engine = JsEngine(baseUrl: key, httpClient: client, cookieStore: cookies,
                              networkSource: .init(key: key, enabledCookieJar: source.enabledCookieJar ?? true, concurrentRate: source.concurrentRate))
        engine.sourceBindingInstaller = { try bridge.install(in: $0, javaAliases: true) }
        engine.libraryInitializer = { context in
            initializer?(context)
            if let library = source.jsLib { context.evaluateScript(library) }
        }
        let result: Any?
        do {
            result = try engine.evaluateScript(script, bindings: bindings, javaMapBindings: mapBindings)
        } catch {
            try await persistCookies(key: key)
            if String(describing: error).contains("Login check rejected") { throw SourceLoginError.rejected }
            throw error
        }
        try await persistCookies(key: key)
        return result
    }

    private func persistCookies(key: String) async throws {
        var row = CookieRow(); row.url = CookieStore.hostKey(key); row.cookie = await cookies.getCookie(url: key)
        try await CookieRepository(database: database).upsert(row)
    }

    private static func isScript(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.hasPrefix("@js:") || text.hasPrefix("<js>")
    }
    private static func script(_ text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("@js:") { return String(text.dropFirst(4)) }
        if text.lowercased().hasPrefix("<js>"), text.lowercased().hasSuffix("</js>") { return String(text.dropFirst(4).dropLast(5)) }
        return text
    }
}
